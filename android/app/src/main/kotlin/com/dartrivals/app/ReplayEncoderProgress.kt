package com.dartrivals.app

/** Count only submitted camera frames, never the opponent's idle turn. */
internal class ReplayEncoderProgress(private val limit: Int = 90) {
    private var framesWithoutSample = 0
    fun frameSubmitted() { framesWithoutSample++ }
    fun sampleWritten() { framesWithoutSample = 0 }
    fun reset() { framesWithoutSample = 0 }
    val stalled: Boolean get() = framesWithoutSample >= limit
}
