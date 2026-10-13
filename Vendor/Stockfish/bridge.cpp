// SPDX-License-Identifier: GPL-3.0-only
// ChessMe adapter for the unmodified, pinned Stockfish 19 engine sources.
#include "ChessMeStockfish.h"
#include "engine.h"
#include "attacks.h"
#include "position.h"
#include "movegen.h"
#include "score.h"
#include <algorithm>
#include <atomic>
#include <chrono>
#include <fstream>
#include <map>
#include <memory>
#include <mutex>
#include <set>
#include <sstream>
#include <thread>
#include <vector>

namespace {
using Clock = std::chrono::steady_clock;
std::mutex engineMutex;
std::unique_ptr<Stockfish::Engine> engine;
std::string loadedNetwork;
std::once_flag initialized;
struct Line { int score; std::vector<std::string> moves; };
struct Snapshot { int depth = 0; uint64_t nodes = 0; std::vector<Line> lines; };

std::vector<std::string> words(const std::string &text) {
    std::istringstream input(text);
    std::vector<std::string> result;
    for (std::string value; input >> value;) result.push_back(value);
    return result;
}
int score(const Stockfish::Score &value) {
    using S = Stockfish::Score;
    if (value.is<S::InternalUnits>()) return value.get<S::InternalUnits>().value;
    if (value.is<S::Mate>()) {
        int plies = value.get<S::Mate>().plies;
        return (plies < 0 ? -1 : 1) * (100000 - std::min(1000, std::abs(plies)));
    }
    return value.get<S::Tablebase>().win ? 20000 : -20000;
}
void option(const std::string &name, const std::string &value) {
    std::istringstream command("name " + name + " value " + value);
    engine->get_options().setoption(command);
}
std::string json(const Snapshot &snapshot, const std::string &limit, int64_t elapsedMilliseconds) {
    std::ostringstream output;
    output << "{\"depth\":" << snapshot.depth << ",\"nodes\":" << snapshot.nodes
           << ",\"elapsedMilliseconds\":" << elapsedMilliseconds
           << ",\"limit\":\"" << limit << "\",\"lines\":[";
    bool first = true;
    for (const auto &line : snapshot.lines) {
        if (!first) output << ',';
        first = false;
        output << "{\"score\":" << line.score << ",\"moves\":[";
        for (size_t i = 0; i < line.moves.size(); ++i) {
            if (i) output << ',';
            output << '"' << line.moves[i] << '"';
        }
        output << "]}";
    }
    output << "]}";
    return output.str();
}
}

int chessme_stockfish_analyze(const char *network, const char *initialFen, const char *uciMoves,
                             const char *requiredMove, int depth, int hashMB, int milliseconds,
                             uint64_t nodes, int threads, void *context,
                             chessme_sf_cancel cancelled, chessme_sf_update update) {
    auto isCancelled = [&] { return cancelled && cancelled(context); };
    std::unique_lock<std::mutex> lock(engineMutex, std::defer_lock);
    while (!lock.try_lock()) {
        if (isCancelled()) return 1;
        std::this_thread::sleep_for(std::chrono::milliseconds(10));
    }
    if (isCancelled()) return 1;
    if (!network || !std::ifstream(network).good()) return 2;
    try {
        std::call_once(initialized, [] { Stockfish::Attacks::init(); Stockfish::Position::init(); });
        if (!engine || loadedNetwork != network) {
            // A path in the resource directory lets the constructor load the
            // network before replicating it to search threads.
            engine = std::make_unique<Stockfish::Engine>(std::filesystem::path(network));
            engine->set_on_verify_network([](std::string_view) {});
            engine->set_on_start([] {});
            option("EvalFile", network);
            option("NumaPolicy", "none");
            loadedNetwork = network;
        }
        if (int(engine->get_options()["Threads"]) != std::clamp(threads, 1, 2))
            option("Threads", std::to_string(std::clamp(threads, 1, 2)));
        if (int(engine->get_options()["Hash"]) != std::clamp(hashMB, 8, 256))
            option("Hash", std::to_string(std::clamp(hashMB, 8, 256)));
        option("UCI_Chess960", "false");
        const auto moves = words(uciMoves ? uciMoves : "");
        if (!initialFen || engine->set_position(initialFen, moves).has_value()) return 3;
        engine->search_clear();
        const int target = std::clamp(depth, 1, 64);
        const std::string required = requiredMove ? requiredMove : "";
        // Reserve a comparable second search when the played move is not in
        // the best three. Both phases share one time and node allowance.
        const auto began = Clock::now();
        const auto deadline = began + std::chrono::milliseconds(std::clamp(milliseconds, 10, 300000));
        uint64_t totalNodes = 0;
        bool interrupted = false;
        Snapshot latest;
        auto run = [&](int multiPV, const std::string &root, int requestedDepth, uint64_t budget,
                       Clock::time_point phaseDeadline) {
            std::map<int, Snapshot> complete;
            std::map<int, std::map<size_t, Line>> iterations;
            std::atomic<bool> finished(false);
            std::mutex updatesMutex;
            auto lastUpdate = Clock::now() - std::chrono::seconds(1);
            uint64_t phaseNodes = 0;
            option("MultiPV", std::to_string(multiPV));
            engine->set_on_update_full([&](const Stockfish::Engine::InfoFull &info) {
                std::lock_guard<std::mutex> guard(updatesMutex);
                phaseNodes = std::max(phaseNodes, static_cast<uint64_t>(info.nodes));
                // output_pv emits a fresh 1...N batch. Later lines can still
                // have the previous depth while the next iteration is partial.
                // Never combine those slots with a prior batch at that depth.
                if (info.multiPV == 1) iterations.clear();
                // Bounds and partial MultiPV iterations cannot grade moves.
                if (!info.bound.empty() || info.depth <= 0 || info.pv.empty()) return;
                iterations[info.depth][info.multiPV] = Line{score(info.score), words(std::string(info.pv))};
                auto &lines = iterations[info.depth];
                if (info.multiPV != static_cast<size_t>(multiPV) || lines.size() != static_cast<size_t>(multiPV)) return;
                Snapshot snapshot{info.depth, totalNodes + phaseNodes, {}};
                std::set<std::string> roots;
                for (size_t i = 1; i <= static_cast<size_t>(multiPV); ++i) {
                    if (!lines.count(i) || lines[i].moves.empty() || !roots.insert(lines[i].moves.front()).second) return;
                    snapshot.lines.push_back(lines[i]);
                }
                complete[info.depth] = snapshot;
                if (root.empty()) latest = snapshot;
                if (update && Clock::now() - lastUpdate >= std::chrono::milliseconds(250)) {
                    auto heartbeat = root.empty() ? snapshot : latest;
                    heartbeat.nodes = totalNodes + phaseNodes;
                    const auto payload = json(heartbeat, "", std::chrono::duration_cast<std::chrono::milliseconds>(Clock::now() - began).count());
                    update(payload.c_str(), context);
                    lastUpdate = Clock::now();
                }
            });
            engine->set_on_update_no_moves([](const Stockfish::Engine::InfoShort &) {});
            engine->set_on_iter([](const Stockfish::Engine::InfoIter &) {});
            engine->set_on_bestmove([&](std::string_view, std::string_view) { finished.store(true); });
            Stockfish::Search::LimitsType limits;
            limits.depth = requestedDepth;
            limits.nodes = std::max<uint64_t>(1, budget);
            limits.startTime = Stockfish::now();
            limits.movetime = std::max<int64_t>(1, std::chrono::duration_cast<std::chrono::milliseconds>(phaseDeadline - Clock::now()).count());
            if (!root.empty()) limits.searchmoves.push_back(root);
            engine->go(limits);
            while (!finished.load()) {
                if (isCancelled()) { interrupted = true; engine->stop(); }
                if (Clock::now() >= phaseDeadline) engine->stop();
                // A deep iteration can take many seconds. Report actual search
                // time without inventing a new depth or mixing partial PVs.
                {
                    std::lock_guard<std::mutex> guard(updatesMutex);
                    if (update && !latest.lines.empty() && Clock::now() - lastUpdate >= std::chrono::seconds(1)) {
                        auto heartbeat = latest;
                        heartbeat.nodes = totalNodes + phaseNodes;
                        const auto payload = json(heartbeat, "", std::chrono::duration_cast<std::chrono::milliseconds>(Clock::now() - began).count());
                        update(payload.c_str(), context);
                        lastUpdate = Clock::now();
                    }
                }
                std::this_thread::sleep_for(std::chrono::milliseconds(10));
            }
            engine->wait_for_search_finished();
            // Do not leave callbacks referring to this stack frame installed.
            engine->set_on_update_full([](const Stockfish::Engine::InfoFull &) {});
            engine->set_on_bestmove([](std::string_view, std::string_view) {});
            totalNodes += phaseNodes;
            return complete;
        };
        // Legal root count is supplied by the Swift adapter through the FEN.
        Stockfish::StateInfo state;
        Stockfish::Position position;
        position.set(engine->fen(), false, &state);
        const int rootCount = static_cast<int>(Stockfish::MoveList<Stockfish::LEGAL>(position).size());
        if (!rootCount) return 3;
        const int multiPV = std::min(3, rootCount);
        const uint64_t budget = std::max<uint64_t>(128, nodes);
        const auto firstDeadline = required.empty() ? deadline : began + (deadline - began) / 2;
        auto best = run(multiPV, "", target, required.empty() ? budget : budget / 2, firstDeadline);
        if (interrupted || isCancelled()) return 1;
        if (best.empty()) return 4;
        Snapshot result = best.rbegin()->second;
        auto hasRequired = [&](const Snapshot &snapshot) {
            return required.empty() || std::any_of(snapshot.lines.begin(), snapshot.lines.end(), [&](const Line &line) {
                return !line.moves.empty() && line.moves.front() == required;
            });
        };
        if (!hasRequired(result)) {
            if (Clock::now() >= deadline || totalNodes >= budget) return 4;
            if (engine->set_position(initialFen, moves).has_value()) return 3;
            auto actual = run(1, required, result.depth, budget - totalNodes, deadline);
            if (interrupted || isCancelled()) return 1;
            bool comparable = false;
            for (auto i = best.rbegin(); i != best.rend(); ++i) {
                if (!actual.count(i->first)) continue;
                result = i->second;
                if (!hasRequired(result)) result.lines.push_back(actual[i->first].lines.front());
                comparable = true;
                break;
            }
            if (!comparable) return 4;
        }
        result.nodes = totalNodes;
        std::stable_sort(result.lines.begin(), result.lines.end(), [](const Line &a, const Line &b) { return a.score > b.score; });
        const auto payload = json(result, result.depth < target ? "Search budget reached" : "",
                                  std::chrono::duration_cast<std::chrono::milliseconds>(Clock::now() - began).count());
        if (update) update(payload.c_str(), context);
        return 0;
    } catch (...) { return 5; }
}

void chessme_stockfish_trim_memory(void) {
    std::unique_lock<std::mutex> lock(engineMutex, std::try_to_lock);
    if (!lock.owns_lock()) return;
    engine.reset();
    loadedNetwork.clear();
}
