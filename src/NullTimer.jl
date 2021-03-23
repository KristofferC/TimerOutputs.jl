struct NullTimer <: AbstractTimerOutput
    name::String
    NullTimer(label::String = "root") = new(label)
end

isdummy(::NullTimer) = true

Base.copy(to::NullTimer) = NullTimer(to.name)

# Add definitions for exported methods
reset_timer!(to::NullTimer) = to
timeit(f::Function, ::NullTimer, ::String) = f()
enable_timer!(::NullTimer) = true
disable_timer!(::NullTimer) = false
flatten(to::NullTimer) = to

ncalls(::NullTimer) = 0
time(::NullTimer) = 0
allocated(::NullTimer) = 0
tottime(::NullTimer) = 0
totallocated(::NullTimer) = 0

complement!(to::NullTimer) = to

Base.haskey(::NullTimer, ::String) = false
Base.getindex(::NullTimer, key::String) = throw(KeyError(key))

function Base.show(io::IO, to::NullTimer)
    print(io, "Timer \"", to.name, "\" is a dummy timer")
end
