#include "CArasan.h"
#include "src/attacks.h"
#include "src/bitutil.h"
#include "src/boardio.h"
#include "src/globals.h"
#include "src/legal.h"
#include "src/notation.h"
#include "src/scoring.h"
#include "src/search.h"
#include <chrono>
#include <mutex>
#include <sstream>
#include <vector>

namespace {
using Clock = std::chrono::steady_clock;
std::timed_mutex engineMutex;
bool initialized = false;

struct Line { int score; std::vector<std::string> moves; };
struct Snapshot { unsigned depth = 0; uint64_t nodes = 0; std::vector<Line> lines; };

int centipawns(score_t value) {
    if (std::abs(value) >= Constants::MATE_RANGE)
        return (value < 0 ? -1 : 1) * (100000 - (Constants::MATE - std::abs(value)));
    return static_cast<int>(value * 100 / Scoring::PAWN_VALUE);
}

Line makeLine(const Board &root, score_t score, const std::array<Move, Constants::MaxPly> &pv) {
    Line line{centipawns(score), {}};
    Board board(root);
    for (Move move : pv) {
        if (IsNull(move) || line.moves.size() == 16 || !legalMove(board, move)) break;
        std::string uci;
        Notation::image(board, move, Notation::OutputFormat::UCI, uci);
        line.moves.push_back(uci);
        board.doMove(move);
    }
    return line;
}

Snapshot snapshot(const Board &root, const Statistics &stats, int count) {
    Snapshot result;
    result.nodes = stats.num_nodes;
    if (count == 1) {
        if (!stats.completedDepth || stats.failHigh || stats.failLow) return result;
        result.depth = stats.completedDepth;
        auto line = makeLine(root, stats.display_value, stats.best_line);
        if (!line.moves.empty()) result.lines.push_back(std::move(line));
    } else {
        const unsigned limit = std::min<unsigned>(count, stats.multipv_limit);
        if (!limit) return result;
        unsigned depth = stats.multi_pvs[0].completedDepth;
        if (!depth) return result;
        for (unsigned i = 0; i < limit; ++i) {
            const auto &pv = stats.multi_pvs[i];
            // Do not combine scores from different or unfinished depth iterations.
            if (pv.completedDepth != depth) return Snapshot{};
            auto line = makeLine(root, pv.display_value, pv.best_line);
            if (!line.moves.empty()) result.lines.push_back(std::move(line));
        }
        result.depth = depth;
    }
    std::sort(result.lines.begin(), result.lines.end(), [](const Line &a, const Line &b) { return a.score > b.score; });
    return result;
}

std::string json(const Snapshot &value, const std::string &limit) {
    std::ostringstream out;
    out << "{\"depth\":" << value.depth << ",\"nodes\":" << value.nodes << ",\"limit\":\"" << limit << "\",\"lines\":[";
    for (size_t i = 0; i < value.lines.size(); ++i) {
        if (i) out << ',';
        const auto &line = value.lines[i];
        out << "{\"score\":" << line.score << ",\"moves\":[";
        for (size_t j = 0; j < line.moves.size(); ++j) {
            if (j) out << ',';
            out << '"' << line.moves[j] << '"';
        }
        out << "]}";
    }
    out << "]}";
    return out.str();
}
}

int chessme_arasan_analyze(const char *network, const char *fen, const char *history,
                          const char *required_move, int depth, int hash_mb,
                          int milliseconds, uint64_t node_limit, void *context,
                          ChessMeArasanCancel cancel, ChessMeArasanUpdate update) {
    auto cancelled = [&] { return cancel && cancel(context); };
    if (cancelled()) return 1;
    std::unique_lock<std::timed_mutex> lock(engineMutex, std::defer_lock);
    while (!lock.try_lock_for(std::chrono::milliseconds(20))) if (cancelled()) return 1;
    if (cancelled()) return 1;
    try {
        if (!initialized) {
            BitUtils::init();
            Board::init();
            Attacks::init();
            Search::init();
            // Desktop initGlobals changes process-wide stack limits and can exit.
            globals::gameMoves = new MoveArray();
            globals::eco = new ECO();
            initialized = true;
        }
        if (!globals::nnueInitDone) {
            if (!network || !globals::loadNetwork(network, false)) return 2;
            globals::nnueInitDone = true;
        }
        Board board;
        if (!fen || !BoardIO::readFEN(board, fen)) return 3;
        // Preserve preceding positions for repetition detection inside variations.
        std::vector<hash_t> hashes;
        std::istringstream records(history ? history : "");
        std::string record;
        while (std::getline(records, record)) {
            Board prior;
            if (BoardIO::readFEN(prior, record + " 0 1")) hashes.push_back(prior.hashCode());
        }
        std::istringstream fenFields(fen);
        std::string field;
        for (int i = 0; i < 4; ++i) fenFields >> field;
        int halfmoves = 0;
        fenFields >> halfmoves;
        halfmoves = std::clamp(halfmoves, 0, 100);
        const size_t available = std::min<size_t>(halfmoves, hashes.size());
        const size_t first = hashes.size() - available;
        board.repListHead = board.repList;
        // Unknown prior positions use impossible hashes, preserving the FEN clock
        // without reading before the beginning of the repetition buffer.
        for (int i = 0; i < halfmoves - static_cast<int>(available); ++i) *board.repListHead++ = 0;
        for (size_t i = first; i < hashes.size(); ++i) *board.repListHead++ = hashes[i];
        *board.repListHead++ = board.hashCode();
        board.state.moveCount = halfmoves;
        board.state.movesFromNull = halfmoves;

        Move required = NullMove;
        if (required_move && *required_move) {
            required = Notation::value(board, board.sideToMove(), Notation::InputFormat::UCI, required_move);
            if (IsNull(required) || !legalMove(board, required)) return 3;
        }
        globals::options.search.ncpus = 1;
        globals::options.search.hash_table_size = size_t(std::clamp(hash_mb, 1, 64)) * 1024 * 1024;
        globals::options.search.can_resign = false;
        globals::options.search.ponder = false;
        globals::options.book.book_enabled = false;
        globals::options.book.eco_enabled = false;
        globals::options.learning.position_learning = false;
        const int targetDepth = std::clamp(depth, 1, 32);
        const auto began = Clock::now();
        const auto deadline = began + std::chrono::milliseconds(std::clamp(milliseconds, 10, 30000));
        auto lastUpdate = began - std::chrono::seconds(2);
        Snapshot best;
        uint64_t totalNodes = 0;
        std::string limit;
        SearchController controller;
        controller.setContempt(0);

        auto run = [&](int count, int target, Clock::time_point end, Move only) {
            controller.setMultiPV(count);
            Snapshot completed;
            Statistics stats;
            controller.registerMonitorFunction([&](SearchController *, const Statistics &current) {
                if (cancelled()) return true;
                if (Clock::now() >= end) { limit = "Time limit"; return true; }
                if (node_limit && totalNodes + current.num_nodes >= node_limit) { limit = "Node limit"; return true; }
                return false;
            });
            controller.registerPostFunction([&](const Statistics &current) {
                auto value = snapshot(board, current, count);
                if (value.depth > 0 && !value.lines.empty()) completed = std::move(value);
                if (IsNull(only) && completed.depth > 0 && Clock::now() - lastUpdate >= std::chrono::seconds(2)) {
                    best = completed;
                    const auto text = json(best, "");
                    if (update) update(text.c_str(), context);
                    lastUpdate = Clock::now();
                }
            });
            MoveSet include, exclude;
            if (!IsNull(only)) include.insert(only);
            // FixedDepth avoids early forced-move exits. The monitor enforces time/nodes.
            controller.findBestMove(board, FixedDepth, 0, 0, target, false, false, stats,
                                    TalkLevel::Silent, exclude, include);
            auto final = snapshot(board, stats, count);
            if (final.depth >= completed.depth && !final.lines.empty()) completed = std::move(final);
            totalNodes += stats.num_nodes;
            return completed;
        };
        const auto primaryEnd = IsNull(required) ? deadline : began + (deadline - began) * 2 / 3;
        best = run(3, targetDepth, primaryEnd, NullMove);
        if (cancelled()) return 1;
        bool alreadyIncluded = false;
        for (const auto &line : best.lines) if (!line.moves.empty() && line.moves.front() == (required_move ? required_move : "")) alreadyIncluded = true;
        if (!IsNull(required) && !alreadyIncluded && best.depth > 0 && Clock::now() < deadline) {
            const auto actual = run(1, best.depth, deadline, required);
            // A lower-depth played-move score cannot fairly grade this decision.
            if (actual.depth >= best.depth && !actual.lines.empty()) best.lines.push_back(actual.lines.front());
        }
        if (cancelled()) return 1;
        std::sort(best.lines.begin(), best.lines.end(), [](const Line &a, const Line &b) { return a.score > b.score; });
        best.nodes = totalNodes;
        const auto result = json(best, limit);
        if (update) update(result.c_str(), context);
        return 0;
    } catch (...) { return 4; }
}
