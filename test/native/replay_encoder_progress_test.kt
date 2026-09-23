package com.dartrivals.app

fun main() {
    val progress = ReplayEncoderProgress()
    // A silent codec (including perpetual dequeueInputBuffer(-1)) recovers
    // after six seconds worth of camera frames, without needing an exception.
    repeat(89) { progress.frameSubmitted(); check(!progress.stalled) }
    progress.frameSubmitted()
    check(progress.stalled)
    progress.reset()
    check(!progress.stalled)
    // Normal encoder latency and long matches do not trigger a restart.
    repeat(10_000) {
        repeat(3) { progress.frameSubmitted(); check(!progress.stalled) }
        progress.sampleWritten()
    }
    // Opponent turns submit no frames and cannot trip the watchdog. Bad
    // output spanning several short own turns still eventually trips it.
    repeat(3) { repeat(30) { progress.frameSubmitted() } }
    check(progress.stalled)
    progress.sampleWritten()
    check(!progress.stalled)
    println("Replay encoder progress: 3 scenarios passed")
}
