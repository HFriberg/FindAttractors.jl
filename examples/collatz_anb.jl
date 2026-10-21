module Collatzanb

using FindAttractors

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
    
    A, B = parse.(T, args[1:2])
    my_next_value, my_max_input = bind_coefficients(Val(A), Val(B))
    
    args = args[3:end]
    stop = isempty(args) ? T(1_000_000) : parse(T, only(args))
    starts = T(1):T(2):stop

    summary = find_attractors(my_next_value, my_max_input, starts; extended_type=UInt128)
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
