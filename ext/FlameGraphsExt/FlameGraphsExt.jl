module FlameGraphsExt

using TimerOutputs
using TimerOutputs: Section, prettytime
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
    root_section = to.root
    # The root frame covers the total time being measured, so start when the
    # timer (or, if cropping, the first section) was created and stop when the
    # last section finished.
    very_start = crop_root ? min_start_time(root_section) : to.start_time
    range = (Int(very_start):Int(max_end_time(root_section, very_start))) .- very_start
    root = Node(NodeData(section_frame(root_section), 0x00, range))
    return _to_flamegraph(root_section, root, very_start)
end


## internals

# Sections are created when first entered, so firstexec is the section's start
section_start(s::Section) = s.firstexec
section_end(s::Section) = section_start(s) + s.time

function min_start_time(s::Section)
    return minimum(section_start(child) for child in values(s.children))
end

function max_end_time(s::Section, self_start)
    self_end = self_start + s.time
    isempty(s.children) && return self_end
    return max(self_end, maximum(max_end_time(child, section_start(child)) for child in values(s.children)))
end

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

function _flamegraph_frame(s::Section, start_ns)
    range = (Int(section_start(s)):Int(section_end(s))) .- start_ns
    return NodeData(section_frame(s), 0x00, range)
end

function _to_flamegraph(s::Section, node, start_ns)
    for child in values(s.children)
        child_node = addchild(node, _flamegraph_frame(child, start_ns))
        _to_flamegraph(child, child_node, start_ns)
    end
    return node
end

end # module
