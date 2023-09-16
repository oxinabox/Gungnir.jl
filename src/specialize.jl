
function specialize_closure(f)
    input_ir = first(only(Base.code_ircode(f, Tuple{})))
    ir = Core.Compiler.copy(input_ir)

    compact = Core.Compiler.IncrementalCompact(ir)
    for ((_, idx), inst) in compact
        ssa = Core.SSAValue(idx)
        if is_known_call(inst, getfield)
            if (
                inst.args[2] == Argument(1) && # if  we are reading one of the closed over fields
                inst.args[3] isa Union{Int, Symbol, QuoteNode}  # and which one is compile time known
                )
                # Instead, insert it directly, so it can be specialized on
                field = inst.args[3]
                (field isa QuoteNode) && (field=field.value)
                value = getfield(f, field)
                compact[ssa][:inst] = value
                compact[ssa][:type] = typeof(value)
            end
        end
    end
    ir = finish(compact)
    return compile(ir)
end

"Runs the compiler pipeline on the IR, returning a callable function"
function compile(ir)
    interp = Core.Compiler.NativeInterpreter()
    mi = get_toplevel_mi_from_ir(ir, @__MODULE__);
    ir = infer_ir!(ir, interp, mi)

    inline_state = Core.Compiler.InliningState(interp)
    ir = Core.Compiler.ssa_inlining_pass!(ir, inline_state, #=propagate_inbounds=#true)
    ir = Core.Compiler.compact!(ir)

    ir = Core.Compiler.sroa_pass!(ir, inline_state)
    ir = Core.Compiler.adce_pass!(ir, inline_state)
    ir = Core.Compiler.compact!(ir)


    # optional but without checking you get segfaults easily.
    Core.Compiler.verify_ir(ir)

    # Bundle this up into something that can be executed
    return Core.OpaqueClosure(ir; do_compile=true)
end