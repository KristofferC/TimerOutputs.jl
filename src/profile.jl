import FlameGraphs

using Base.StackTraces: StackFrame
using LeftChildRightSiblingTrees: Node, addchild

function max_end_time(to::TimerOutput)
    return maximum(child.start_data.time + child.accumulated_data.time for child in values(to.inner_timers))
end

# Make a flat frame for this TimerOutput
function _flamegraph_frame(to::TimerOutput, start_ns; toplevel = false)
    # TODO: Use a better conversion to a StackFrame so this contains the right kind of data
    tt = Symbol(to.name)
    sf = StackFrame(tt, Symbol("none"), 0, nothing, false, false, UInt64(0x0))
    status = 0x0  # "default" status -- See FlameGraphs.jl
    start = to.start_data.time - start_ns
    # TODO: is this supposed to be inclusive or exclusive?
    if toplevel
        # The root frame covers the total time being measured, so start when the first node
        # was created, and stop when the last node was finished.
        range = Int(start) : Int(start + (max_end_time(to) - start_ns))
    else
        #range = Int(start) : Int(start + TimerOutputs.tottime(to))
        range = Int(start) : Int(start + to.accumulated_data.time)
    end
    return FlameGraphs.NodeData(sf, status, range)
end

function to_flamegraph(to::TimerOutput)
    # Skip the very top-level node, which contains no useful data
    node_data = _flamegraph_frame(to, to.start_data.time; toplevel=true)
    root = Node(node_data)
    return _to_flamegraph(to, root, to.start_data.time)
end
function _to_flamegraph(to::TimerOutput, root, start_ns)
    for (k, child) in to.inner_timers
        node_data = _flamegraph_frame(child, start_ns)
        node = addchild(root, node_data)
        _to_flamegraph(child, node, start_ns)
    end
    return root
end
