module Collatz5n3

using FindAttractors

function next_value(value)
    value = 5 * value + 3
    return value >> trailing_zeros(value)
end

max_input(::Type{T}) where T = T((typemax(T) - 3) ÷ 5)

function main(args=ARGS)
    T = UInt64
    stop = isempty(args) ? T(1_000_000) : parse(T, only(args))
    starts = T(1):T(2):stop
    summary = find_attractors(next_value, max_input, starts; extended_type=UInt128)
    println("Tested ", summary.processed, " starts in ", summary.elapsed, " seconds; ",
            summary.cycles, " cycle entries, ", summary.overflow, " overflow.")
    return summary
end

if abspath(PROGRAM_FILE) == @__FILE__
    Base.exit_on_sigint(false)
    try
        main()
    catch error
        if error isa InterruptException
            println(stderr, "\nInterrupted by user.")
        else
            rethrow()
        end
    end
end

end
