module FlameGraphsExt

using TimerOutputs
using TimerOutputs: prettytime
using FlameGraphs: FlameGraphs, NodeData
using FlameGraphs.LeftChildRightSiblingTrees: Node, addchild
using Base.StackTraces: StackFrame

"""
    flamegraph(to::TimerOutput; crop_root = false)

Create a flamegraph from a TimerOutput. The flamegraph will show the time spent in each
function, with the width of each box proportional to the time spent in that function.
Use `crop_root = true` to crop the root node to the first and last child nodes.
"""
function FlameGraphs.flamegraph(to::TimerOutput; crop_root = false)
    # Skip the very top-level node, which contains no useful data
    very_start = crop_root ? min_start_time(to) : to.start_data.time
    node_data = _flamegraph_frame(to, very_start; toplevel=true, crop_root)
    root = Node(node_data)
    return _to_flamegraph(to, root, very_start)
end

## internals

function min_start_time(to::TimerOutput)
    return minimum(child.start_data.time for child in values(to.inner_timers))
end

function max_end_time(to::TimerOutput)
    self_end = to.start_data.time + to.accumulated_data.time
    if isempty(to.inner_timers)
        return self_end
    end
    # Compute max end time considering both direct end time and all inner timers
    return max(self_end, maximum(max_end_time(child) for child in values(to.inner_timers)))
end

# Make a flat frame for this TimerOutput
function _flamegraph_frame(to::TimerOutput, start_ns; toplevel = false, crop_root = true)
    # TODO: Use a better conversion to a StackFrame so this contains the right kind of data
    nc = to.accumulated_data.ncalls
    tt_str = string(to.name, " (", strip(prettytime(to.accumulated_data.time)))
    if to.accumulated_data.ncalls > 1
        avg = to.accumulated_data.time / to.accumulated_data.ncalls
        tt_str *= string(": ", nc, " calls ", strip(prettytime(avg)), " avg")
    end
    tt_str *= ")"
    tt = Symbol(tt_str)
    # Set the pointer to ensure the sf is unique
    sf = StackFrame(tt, Symbol("none"), 0, nothing, false, false, Base.objectid(to))
    status = 0x0  # "default" status -- See FlameGraphs.jl
    # TODO: is this supposed to be inclusive or exclusive?
    if toplevel
        # The root frame covers the total time being measured, so start when the first node
        # was created, and stop when the last node was finished.
        _start = crop_root ? min_start_time(to) : to.start_data.time
        _end = max_end_time(to)
        range = (Int(_start) : Int(_end)) .- start_ns
    else
        #range = Int(start) : Int(start + TimerOutputs.tottime(to))
        _start = to.start_data.time
        _end = to.start_data.time + to.accumulated_data.time
        range = (Int(_start) : Int(_end)) .- start_ns
    end
    return FlameGraphs.NodeData(sf, status, range)
end

function _to_flamegraph(to::TimerOutput, root, start_ns)
    for (k, child) in to.inner_timers
        node_data = _flamegraph_frame(child, start_ns)
        node = addchild(root, node_data)
        _to_flamegraph(child, node, start_ns)
    end
    return root
end

end # module
