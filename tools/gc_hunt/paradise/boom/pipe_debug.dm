// Local test, not part of any PR. Who puts a deleted pipe or machine into a pipeline: logged to data/boom/gc_hunt.txt with the chain.

GLOBAL_VAR_INIT(pd_logs, 0)

/proc/pd_chain(callee/step)
	var/list/chain = list()
	while(step && length(chain) < 9)
		chain += "[step.proc]"
		step = step.caller
	return jointext(chain, " < ")

/proc/pd_log(text)
	if(GLOB.pd_logs < 60)
		GLOB.pd_logs++
		text2file("[round(world.time / 10)]s: [text]", "data/boom/gc_hunt.txt")

/datum/pipeline/addMachineryMember(obj/machinery/atmospherics/A)
	if(QDELETED(A))
		pd_log("deleted [A.type] added as machinery: [pd_chain(caller)]")
	return ..()

/datum/pipeline/build_pipeline(obj/machinery/atmospherics/base)
	if(QDELETED(base))
		pd_log("pipeline built from deleted [base.type]: [pd_chain(caller)]")
	. = ..()
	for(var/obj/machinery/atmospherics/pipe/P in members)
		if(QDELETED(P))
			pd_log("pipeline from [base.type] took in deleted [P.type]: [pd_chain(caller)]")

/datum/pipeline/addMember(obj/machinery/atmospherics/A, obj/machinery/atmospherics/N)
	if(QDELETED(A))
		pd_log("deleted [A.type] added as a member, from [N?.type]: [pd_chain(caller)]")
	return ..()
