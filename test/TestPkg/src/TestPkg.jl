module TestPkg

using TimerOutputs

const TIMER = TimerOutput()

@timeit TIMER function abc()
    1 + 1
end

end # module TestPkg
