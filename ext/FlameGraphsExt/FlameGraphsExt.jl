module FlameGraphsExt

using TimerOutputs: TimerOutput, Section, prettytime
using FlameGraphs: FlameGraphs, NodeData
using FlameGraphs.LeftChildRightSiblingTrees: Node, addchild
using Base.StackTraces: StackFrame

"""
    flamegraph(to::TimerOutput; crop_root = false)

Create a flamegraph from a TimerOutput. The flamegraph will show the time spent in each
function, with the width of each box proportional to its accumulated time.
Sections are laid out consecutively, not at their original timestamps: the timer
does not retain individual invocations. Use `crop_root = true` to omit untimed
wall time from the root. Children whose total exceeds their parent's time
(for example, after merging parallel work) are scaled to fit the parent.
"""
function FlameGraphs.flamegraph(to::TimerOutput; crop_root = false)
    root_section = to.root
    measured = child_time(root_section)
    duration = crop_root ? measured : max(measured, Int(time_ns()) - to.start_time)
    range = 0:(max(duration, 1) - 1)
    root = Node(NodeData(section_frame(root_section), 0x00, range))
    return _to_flamegraph(root_section, root)
end


## internals

child_time(s::Section) = sum(c -> max(c.time, 0), s.children; init = Int64(0))

function section_frame(s::Section)
    # TODO: Use a better conversion to a StackFrame so this contains the right kind of data
    label = string(s.name, " ", strip(prettytime(s.time)))
    if s.ncalls > 1
        avg = s.time / s.ncalls
        label *= string(" ", s.ncalls, "×μ", strip(prettytime(avg)))
    end
    # Set the pointer to ensure the sf is unique
    return StackFrame(Symbol(label), Symbol("none"), 0, nothing, false, false, Base.objectid(s))
end

function _to_flamegraph(s::Section, node)
    span = node.data.span
    start = first(span)
    total = child_time(s)
    available = length(span)
    for child in s.children
        duration = max(child.time, 0)
        if total > available
            duration = Int(div(widemul(duration, available), total))
        end
        child_span = start:(start + duration - 1)
        child_node = addchild(node, NodeData(section_frame(child), 0x00, child_span))
        _to_flamegraph(child, child_node)
        start += duration
    end
    return node
end

end # module
