/mob/living/silicon/robot/update_icons()
    if(module?.hippie_cyborg_base_icon)
        module.cyborg_base_icon = module.hippie_cyborg_base_icon // the Hippie skins are merged into icons/mob/robots.dmi
    return ..()