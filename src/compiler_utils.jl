using Core.Compiler
const CC = Core.Compiler
using Core: SSAValue, Argument
using Core.Compiler: IRCode, Instruction, InstructionStream, IncrementalCompact,
    NewInstruction, DomTree, BBIdxIter, AnySSAValue, UseRef, UseRefIterator,
    block_for_inst, cfg_simplify!, is_known_call, argextype, getfield_tfunc, finish,
    singleton_type, widenconst, dominates_ssa, ⊑, userefs


"Given some IR generates a MethodInstance suitable for passing to infer_ir!, if you don't already have one with the right argument types"
function get_toplevel_mi_from_ir(ir, _module::Module)
    mi = ccall(:jl_new_method_instance_uninit, Ref{Core.MethodInstance}, ());
    mi.specTypes = Tuple{ir.argtypes...}
    mi.def = _module
    return mi
end

"run type inference and constant propagation on the ir"
function infer_ir!(ir, interp::Core.Compiler.AbstractInterpreter, mi::Core.Compiler.MethodInstance)
    method_info = Core.Compiler.MethodInfo(#=propagate_inbounds=#true, nothing)
    min_world = world = Core.Compiler.get_world_counter(interp)
    max_world = Base.get_world_counter()
    irsv = Core.Compiler.IRInterpretationState(interp, method_info, ir, mi, ir.argtypes, world, min_world, max_world)
    rt = Core.Compiler._ir_abstract_constant_propagation(interp, irsv)
    return ir
end


# add overloads from Core.Compiler into Base
# Diffractor has a bunch of these, we need to make a library for them
# https://github.com/JuliaDiff/Diffractor.jl/blob/b23337a4b12d21104ff237cf0c72bcd2fe13a4f6/src/stage1/hacks.jl
# https://github.com/JuliaDiff/Diffractor.jl/blob/b23337a4b12d21104ff237cf0c72bcd2fe13a4f6/src/stage1/recurse.jl#L238-L247
# https://github.com/JuliaDiff/Diffractor.jl/blob/b23337a4b12d21104ff237cf0c72bcd2fe13a4f6/src/stage1/compiler_utils.jl

Base.iterate(compact::IncrementalCompact, state) = Core.Compiler.iterate(compact, state)
Base.iterate(compact::IncrementalCompact) = Core.Compiler.iterate(compact)
Base.iterate(abu::CC.AbsIntStackUnwind, state...) = CC.iterate(abu, state...)

Base.setindex!(compact::IncrementalCompact, @nospecialize(v), idx::SSAValue) = Core.Compiler.setindex!(compact,v,idx)
Base.setindex!(ir::IRCode, @nospecialize(v), idx::SSAValue) = Core.Compiler.setindex!(ir,v,idx)
Base.setindex!(inst::Instruction, @nospecialize(v), sym::Symbol) = Core.Compiler.setindex!(inst,v,sym)
Base.getindex(compact::IncrementalCompact, idx::AnySSAValue) = Core.Compiler.getindex(compact,idx)

Base.setindex!(urs::InstructionStream, @nospecialize args...) = Core.Compiler.setindex!(urs, args...)
Base.setindex!(ir::IRCode, @nospecialize args...) = Core.Compiler.setindex!(ir, args...)
Base.getindex(ir::IRCode, @nospecialize args...) = Core.Compiler.getindex(ir, args...)

Base.IteratorSize(::Type{CC.AbsIntStackUnwind}) = Base.SizeUnknown()


is_known_call(::Any, ::Any) = false
function is_known_call(stmt::Expr, f)
    Meta.isexpr(stmt, :call) || return false
    length(stmt.args) >= 1 || return false
    target = stmt.args[1]
    target == f && return true
    if target isa GlobalRef
        binding = target.binding
        while(!isdefined(binding, :value))
            binding=binding.owner
        end
        return binding.value == f
    end
    @warn "Target not supported" && return false 
end