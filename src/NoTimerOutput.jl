struct NoTimerOutput <: AbstractTimerOutput
    name::String
    NoTimerOutput(label::String = "root") = new(label)
end

isdummy(::NoTimerOutput) = true

Base.copy(to::NoTimerOutput) = NoTimerOutput(to.name)

# Add definitions for exported methods
reset_timer!(to::NoTimerOutput) = to
timeit(f::Function, ::NoTimerOutput, ::String) = f()
enable_timer!(to::NoTimerOutput) = true
disable_timer!(to::NoTimerOutput) = false

function Base.show(io::IO, to::NoTimerOutput)
    # TODO modify this?
    print(io, "Timer \"", to.name, "\" is a dummy timer")
end
