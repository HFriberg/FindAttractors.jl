module Collatz5n3

using FindAttractors
using ArgParse

function collatz_cli_settings(T)
    settings = cli_settings(T)
    settings.description = "Search for attractors of the odd-to-odd 5*n+3 Collatz sequence."
    return settings
end

function next_value(value)
    value = 5 * value + 3
    return value >> trailing_zeros(value)
end

max_input(::Type{T}) where T = T((typemax(T) - 3) ÷ 5)

function main(args=ARGS)
    T = UInt64
    options = parse_args(args, collatz_cli_settings(T))

    starts = T(1):T(2):options["to"].value
    firststart = searchsortedfirst(starts, options["from"].value)
    starts = starts[firststart:end]

    summary = find_attractors(next_value, max_input, starts; extended_type=UInt128, maxtime=options["maxtime"])
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
