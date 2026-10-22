module Collatzanb

using FindAttractors
using ArgParse

function collatz_cli_settings(T)
    settings = cli_settings(T)
    settings.description = "Search for attractors of the odd-to-odd A*n+B Collatz sequence."

    @add_arg_table! settings begin
        "A"
            help = "odd multiplier"
            arg_type = T
            required = true
            range_tester = isodd
        "B"
            help = "odd offset"
            arg_type = T
            required = true
            range_tester = isodd
    end

    return settings
end

function next_value(::Val{A}, ::Val{B}, value::T) where {A,B,T}
    value = A * value + B
    return value >> trailing_zeros(value)
end

max_input(::Val{A}, ::Val{B}, ::Type{T}) where {A,B,T} = T((typemax(T) - B) ÷ A)

function bind_coefficients(a::Val{A}, b::Val{B}) where {A,B}
    my_next_value = value -> next_value(a, b, value)
    my_max_input = T -> max_input(a, b, T)
    return my_next_value, my_max_input
end

function main(args=ARGS)
    T = UInt64
    options = parse_args(args, collatz_cli_settings(T))

    A, B = options["A"], options["B"]
    my_next_value, my_max_input = bind_coefficients(Val(A), Val(B))
    
    starts = T(1):T(2):options["to"].value
    firststart = searchsortedfirst(starts, options["from"].value)
    starts = starts[firststart:end]

    summary = find_attractors(my_next_value, my_max_input, starts; extended_type=UInt128, maxtime=options["maxtime"])
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
