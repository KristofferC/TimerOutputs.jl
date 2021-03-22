struct NoTimerOutput <: AbstractTimerOutput
    name::String
    NoTimerOutput(label::String = "root") = new(label)
end

isdummy(::NoTimerOutput) = true

Base.copy(to::NoTimerOutput) = NoTimerOutput(to.name)

# Add definitions for exported methods
reset_timer!(to::NoTimerOutput) = to
timeit(f::Function, ::NoTimerOutput, ::String) = f()
enable_timer!(::NoTimerOutput) = true
disable_timer!(::NoTimerOutput) = false
flatten(to::NoTimerOutput) = to

ncalls(::NoTimerOutput) = 0
time(::NoTimerOutput) = 0
allocated(::NoTimerOutput) = 0
tottime(::NoTimerOutput) = 0
totallocated(::NoTimerOutput) = 0

complement!(to::NoTimerOutput) = to

Base.haskey(::NoTimerOutput, ::String) = false
Base.getindex(::NoTimerOutput, key::String) = throw(KeyError(key))

function Base.show(io::IO, to::NoTimerOutput)
    print(io, "Timer \"", to.name, "\" is a dummy timer")
end
