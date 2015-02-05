#define APC_WIRE_IDSCAN 1
#define APC_WIRE_MAIN_POWER1 2
#define APC_WIRE_MAIN_POWER2 3
#define APC_WIRE_AI_CONTROL 4

//update_state
#define UPSTATE_CELL_IN 1
#define UPSTATE_OPENED1 2
#define UPSTATE_OPENED2 4
#define UPSTATE_MAINT 8
#define UPSTATE_BROKE 16
#define UPSTATE_BLUESCREEN 32
#define UPSTATE_WIREEXP 64
#define UPSTATE_ALLGOOD 128

//update_overlay
#define APC_UPOVERLAY_CHARGEING0 1
#define APC_UPOVERLAY_CHARGEING1 2
#define APC_UPOVERLAY_CHARGEING2 4
#define APC_UPOVERLAY_EQUIPMENT0 8
#define APC_UPOVERLAY_EQUIPMENT1 16
#define APC_UPOVERLAY_EQUIPMENT2 32
#define APC_UPOVERLAY_LIGHTING0 64
#define APC_UPOVERLAY_LIGHTING1 128
#define APC_UPOVERLAY_LIGHTING2 256
#define APC_UPOVERLAY_ENVIRON0 512
#define APC_UPOVERLAY_ENVIRON1 1024
#define APC_UPOVERLAY_ENVIRON2 2048
#define APC_UPOVERLAY_LOCKED 4096
#define APC_UPOVERLAY_OPERATING 8192

#define APC_UPDATE_ICON_COOLDOWN 100 // 10 seconds


// the Area Power Controller (APC), formerly Power Distribution Unit (PDU)
// one per area, needs wire conection to power network through a terminal

// controls power to devices in that area
// may be opened to change power cell
// three different channels (lighting/equipment/environ) - may each be set to on, off, or auto


//NOTE: STUFF STOLEN FROM AIRLOCK.DM thx


/obj/machinery/power/apc
	desc = "A control terminal for the area electrical systems."
	icon_state = "apc0"
	anchored = 1
	use_power = 0
	req_access = list(access_engine_equip)
	var/spooky=0
	var/obj/item/weapon/cell/cell
	var/start_charge = 90				// initial cell charge %
	var/cell_type = 2500				// 0=no cell, 1=regular, 2=high-cap (x5) <- old, now it's just 0=no cell, otherwise dictate cellcapacity by changing this value. 1 used to be 1000, 2 was 2500
	var/opened = 0                      //0=closed, 1=opened, 2=cover removed
	var/shorted = 0
	var/lighting = 3
	var/equipment = 3
	var/environ = 3
	var/operating = 1
	var/charging = 0
	var/chargemode = 1
	var/chargecount = 0
	var/locked = 1
	var/coverlocked = 1
	var/aidisabled = 0
	var/tdir = null
	var/obj/machinery/power/terminal/terminal = null
	var/lastused_light = 0
	var/lastused_equip = 0
	var/lastused_environ = 0
	var/lastused_total = 0
	var/main_status = 0
	var/wiresexposed = 0
	powernet = 0		// set so that APCs aren't found as powernet nodes //Hackish, Horrible, was like this before I changed it :(
	var/malfhack = 0 //New var for my changes to AI malf. --NeoFite
	var/mob/living/silicon/ai/malfai = null //See above --NeoFite
//	luminosity = 1
	var/has_electronics = 0 // 0 - none, 1 - plugged in, 2 - secured by screwdriver
	var/overload = 1 //used for the Blackout malf module
	var/beenhit = 0 // used for counting how many times it has been hit, used for Aliens at the moment
	var/mob/living/silicon/ai/occupant = null
	var/longtermpower = 10
	var/update_state = -1
	var/update_overlay = -1
	var/global/status_overlays = 0
	var/updating_icon = 0
	var/datum/wires/apc/wires = null
	var/global/list/status_overlays_lock
	var/global/list/status_overlays_charging
	var/global/list/status_overlays_equipment
	var/global/list/status_overlays_lighting
	var/global/list/status_overlays_environ

	var/is_critical = 0 // Endgame scenarios will not destroy this APC.

/obj/machinery/power/apc/New(loc, var/ndir, var/building=0)
	..(loc)
	wires = new(src)
	// offset 24 pixels in direction of dir
	// this allows the APC to be embedded in a wall, yet still inside an area
	if (building)
		dir = ndir
	src.tdir = dir		// to fix Vars bug
	dir = SOUTH

	if(src.tdir & 3)
		pixel_x = 0
		pixel_y = (src.tdir == 1 ? 24 : -24)
	else
		pixel_x = (src.tdir == 4 ? 24 : -24)
		pixel_y = 0

	if (building==0)
		init()
	else
		opened = 1
		operating = 0
		stat |= MAINT

	if(ticker)
		initialize()

/obj/machinery/power/apc/proc/init()
	has_electronics = 2 //installed and secured
	// is starting with a power cell installed, create it and set its charge level
	if(cell_type)
		src.cell = new/obj/item/weapon/cell(src)
		cell.maxcharge = cell_type	// cell_type is maximum charge (old default was 1000 or 2500 (values one and two respectively)
		cell.charge = start_charge * cell.maxcharge / 100.0 		// (convert percentage to actual value)

	make_terminal()

/obj/machinery/power/apc/proc/make_terminal()
	// create a terminal object at the same position as original turf loc
	// wires will attach to this
	terminal = new/obj/machinery/power/terminal(src.loc)
	terminal.dir = tdir
	terminal.master = src

/obj/machinery/power/apc/initialize()
	..()

	name = "[areaMaster.name] APC"

	update_icon()

	spawn(5)
		update()

/obj/machinery/power/apc/examine(mob/user)
	..()
	if(stat & BROKEN)
		user << "Looks broken."
		return
	if(opened)
		if(has_electronics && terminal)
			user << "The cover is [opened==2?"removed":"open"] and the power cell is [ cell ? "installed" : "missing"]."
		else if (!has_electronics && terminal)
			user << "There are some wires but no any electronics."
		else if (has_electronics && !terminal)
			user << "Electronics installed but not wired."
		else /* if (!has_electronics && !terminal) */
			user << "There is no electronics nor connected wires."
	else
		if (stat & MAINT)
			user << "The cover is closed. Something wrong with it: it doesn't work."
		else if (malfhack)
			user << "The cover is broken. It may be hard to force it open."
		else
			user << "The cover is closed."

/obj/machinery/power/apc/update_icon()
	if (!status_overlays)
		status_overlays = 1
		status_overlays_lock = new
		status_overlays_charging = new
		status_overlays_equipment = new
		status_overlays_lighting = new
		status_overlays_environ = new

		status_overlays_lock.len = 2
		status_overlays_charging.len = 3
		status_overlays_equipment.len = 4
		status_overlays_lighting.len = 4
		status_overlays_environ.len = 4

		status_overlays_lock[1] = image(icon, "apcox-0")    // 0=blue 1=red
		status_overlays_lock[2] = image(icon, "apcox-1")

		status_overlays_charging[1] = image(icon, "apco3-0")
		status_overlays_charging[2] = image(icon, "apco3-1")
		status_overlays_charging[3] = image(icon, "apco3-2")

		status_overlays_equipment[1] = image(icon, "apco0-0") // 0=red, 1=green, 2=blue
		status_overlays_equipment[2] = image(icon, "apco0-1")
		status_overlays_equipment[3] = image(icon, "apco0-2")
		status_overlays_equipment[4] = image(icon, "apco0-3")

		status_overlays_lighting[1] = image(icon, "apco1-0")
		status_overlays_lighting[2] = image(icon, "apco1-1")
		status_overlays_lighting[3] = image(icon, "apco1-2")
		status_overlays_lighting[4] = image(icon, "apco1-3")

		status_overlays_environ[1] = image(icon, "apco2-0")
		status_overlays_environ[2] = image(icon, "apco2-1")
		status_overlays_environ[3] = image(icon, "apco2-2")
		status_overlays_environ[4] = image(icon, "apco2-3")



	var/update = check_updates() 		//returns 0 if no need to update icons.
						// 1 if we need to update the icon_state
						// 2 if we need to update the overlays
	if(!update)
		return

	if(update & 1) // Updating the icon state
		if(update_state & UPSTATE_ALLGOOD)
			icon_state = "apc0"
		else if(update_state & (UPSTATE_OPENED1|UPSTATE_OPENED2))
			var/basestate = "apc[ cell ? "2" : "1" ]"
			if(update_state & UPSTATE_OPENED1)
				if(update_state & (UPSTATE_MAINT|UPSTATE_BROKE))
					icon_state = "apcmaint" //disabled APC cannot hold cell
				else
					icon_state = basestate
			else if(update_state & UPSTATE_OPENED2)
				icon_state = "[basestate]-nocover"
		else if(update_state & UPSTATE_BROKE)
			icon_state = "apc-b"
		else if(update_state & UPSTATE_BLUESCREEN)
			icon_state = "apcemag"
		else if(update_state & UPSTATE_WIREEXP)
			icon_state = "apcewires"



	if(!(update_state & UPSTATE_ALLGOOD))
		if(overlays.len)
			overlays = 0
			return
	if(update & 2)

		if(overlays.len)
			overlays = 0

		if(!(stat & (BROKEN|MAINT)) && update_state & UPSTATE_ALLGOOD)
			overlays += status_overlays_lock[locked+1]
			overlays += status_overlays_charging[charging+1]
			if(operating)
				overlays += status_overlays_equipment[equipment+1]
				overlays += status_overlays_lighting[lighting+1]
				overlays += status_overlays_environ[environ+1]


/obj/machinery/power/apc/proc/check_updates()

	var/last_update_state = update_state
	var/last_update_overlay = update_overlay
	update_state = 0
	update_overlay = 0

	if(cell)
		update_state |= UPSTATE_CELL_IN
	if(stat & BROKEN)
		update_state |= UPSTATE_BROKE
	if(stat & MAINT)
		update_state |= UPSTATE_MAINT

	if(opened)
		if(opened==1)
			update_state |= UPSTATE_OPENED1
		if(opened==2)
			update_state |= UPSTATE_OPENED2
	else if(emagged || malfai || spooky)
		update_state |= UPSTATE_BLUESCREEN
	else if(wiresexposed)
		update_state |= UPSTATE_WIREEXP
	if(update_state <= 1)
		update_state |= UPSTATE_ALLGOOD

	if(operating)
		update_overlay |= APC_UPOVERLAY_OPERATING

	if(update_state & UPSTATE_ALLGOOD)
		if(locked)
			update_overlay |= APC_UPOVERLAY_LOCKED

		if(!charging)
			update_overlay |= APC_UPOVERLAY_CHARGEING0
		else if(charging == 1)
			update_overlay |= APC_UPOVERLAY_CHARGEING1
		else if(charging == 2)
			update_overlay |= APC_UPOVERLAY_CHARGEING2

		if (!equipment)
			update_overlay |= APC_UPOVERLAY_EQUIPMENT0
		else if(equipment == 1)
			update_overlay |= APC_UPOVERLAY_EQUIPMENT1
		else if(equipment == 2)
			update_overlay |= APC_UPOVERLAY_EQUIPMENT2

		if(!lighting)
			update_overlay |= APC_UPOVERLAY_LIGHTING0
		else if(lighting == 1)
			update_overlay |= APC_UPOVERLAY_LIGHTING1
		else if(lighting == 2)
			update_overlay |= APC_UPOVERLAY_LIGHTING2

		if(!environ)
			update_overlay |= APC_UPOVERLAY_ENVIRON0
		else if(environ==1)
			update_overlay |= APC_UPOVERLAY_ENVIRON1
		else if(environ==2)
			update_overlay |= APC_UPOVERLAY_ENVIRON2

	var/results = 0
	if(last_update_state == update_state && last_update_overlay == update_overlay)
		return 0
	if(last_update_state != update_state)
		results += 1
	if(last_update_overlay != update_overlay && update_overlay != 0)
		results += 2
	return results




// Used in process so it doesn't update the icon too much
/obj/machinery/power/apc/proc/queue_icon_update()

	if(!updating_icon)
		updating_icon = 1
		// Start the update
		spawn(APC_UPDATE_ICON_COOLDOWN)
			update_icon()
			updating_icon = 0

/obj/machinery/power/apc/proc/spookify()
	if(spooky) return // Fuck you we're already spooky
	spooky=1
	update_icon()
	spawn(10)
		spooky=0
		update_icon()

//attack with an item - open/close cover, insert cell, or (un)lock interface
/obj/machinery/power/apc/attackby(obj/item/W, mob/user)

	if (istype(user, /mob/living/silicon) && get_dist(src,user)>1)
		return src.attack_hand(user)
	src.add_fingerprint(user)
	if (istype(W, /obj/item/weapon/crowbar) && opened)
		if (has_electronics==1)
			if (terminal)
				user << "\red Disconnect wires first."
				return
			playsound(get_turf(src), 'sound/items/Crowbar.ogg', 50, 1)
			user << "You are trying to remove the power control board..." //lpeters - fixed grammar issues
			if(do_after(user, 50))
				has_electronics = 0
				if ((stat & BROKEN) || malfhack)
					user.visible_message(\
						"\red [user.name] has broken the power control board inside [src.name]!",\
						"You broke the charred power control board and remove the remains.",
						"You hear a crack!")
					//ticker.mode:apcs-- //XSI said no and I agreed. -rastaf0
				else
					user.visible_message(\
						"\red [user.name] has removed the power control board from [src.name]!",\
						"You remove the power control board.")
					new /obj/item/weapon/module/power_control(loc)
		else if (opened!=2) //cover isn't removed
			opened = 0
			update_icon()
	else if (istype(W, /obj/item/weapon/crowbar) && !((stat & BROKEN) || malfhack) )
		if(coverlocked && !(stat & MAINT))
			user << "\red The cover is locked and cannot be opened."
			return
		else
			opened = 1
			update_icon()
	else if	(istype(W, /obj/item/weapon/cell) && opened)	// trying to put a cell inside
		if(cell)
			user << "There is a power cell already installed."
			return
		else
			if (stat & MAINT)
				user << "\red There is no connector for your power cell."
				return
			user.drop_item()
			W.loc = src
			cell = W
			user.visible_message(\
				"\red [user.name] has inserted the power cell to [src.name]!",\
				"You insert the power cell.")
			chargecount = 0
			update_icon()
	else if	(istype(W, /obj/item/weapon/screwdriver))	// haxing
		if(opened)
			if (cell)
				user << "\red Close the APC first." //Less hints more mystery!
				return
			else
				if (has_electronics==1 && terminal)
					has_electronics = 2
					stat &= ~MAINT
					playsound(get_turf(src), 'sound/items/Screwdriver.ogg', 50, 1)
					user << "You screw the circuit electronics into place."
				else if (has_electronics==2)
					has_electronics = 1
					stat |= MAINT
					playsound(get_turf(src), 'sound/items/Screwdriver.ogg', 50, 1)
					user << "You unfasten the electronics."
				else /* has_electronics==0 */
					user << "\red There is nothing to secure."
					return
				update_icon()
		else if(emagged)
			user << "The interface is broken."
		else
			wiresexposed = !wiresexposed
			user << "The wires have been [wiresexposed ? "exposed" : "unexposed"]"
			update_icon()

	else if (istype(W, /obj/item/weapon/card/id)||istype(W, /obj/item/device/pda))			// trying to unlock the interface with an ID card
		if(emagged)
			user << "The interface is broken."
		else if(opened)
			user << "You must close the cover to swipe an ID card."
		else if(wiresexposed)
			user << "You must close the panel"
		else if(stat & (BROKEN|MAINT))
			user << "Nothing happens."
		else
			if(src.allowed(usr) && !isWireCut(APC_WIRE_IDSCAN))
				locked = !locked
				user << "You [ locked ? "lock" : "unlock"] the APC interface."
				update_icon()
			else
				user << "\red Access denied."
	else if (istype(W, /obj/item/weapon/card/emag) && !(emagged || malfhack))		// trying to unlock with an emag card
		if(opened)
			user << "You must close the cover to swipe an ID card."
		else if(wiresexposed)
			user << "You must close the panel first"
		else if(stat & (BROKEN|MAINT))
			user << "Nothing happens."
		else
			flick("apc-spark", src)
			if (do_after(user,6))
				if(prob(50))
					emagged = 1
					locked = 0
					user << "You emag the APC interface."
					update_icon()
				else
					user << "You fail to [ locked ? "unlock" : "lock"] the APC interface."
	else if (istype(W, /obj/item/weapon/cable_coil) && !terminal && opened && has_electronics!=2)
		if (src.loc:intact)
			user << "\red You must remove the floor plating in front of the APC first."
			return
		var/obj/item/weapon/cable_coil/C = W
		if(C.amount < 10)
			user << "\red You need more wires."
			return
		user << "You start adding cables to the APC frame..."
		playsound(get_turf(src), 'sound/items/Deconstruct.ogg', 50, 1)
		if(do_after(user, 20) && C.amount >= 10)
			var/turf/T = get_turf_loc(src)
			var/obj/structure/cable/N = T.get_cable_node()
			if (prob(50) && electrocute_mob(usr, N, N))
				var/datum/effect/effect/system/spark_spread/s = new /datum/effect/effect/system/spark_spread
				s.set_up(5, 1, src)
				s.start()
				return
			C.use(10)
			user.visible_message(\
				"\red [user.name] has added cables to the APC frame!",\
				"You add cables to the APC frame.")
			make_terminal()
			terminal.connect_to_network()
	else if (istype(W, /obj/item/weapon/wirecutters) && terminal && opened && has_electronics!=2)
		if (src.loc:intact)
			user << "\red You must remove the floor plating in front of the APC first."
			return
		user << "You begin to cut the cables..."
		playsound(get_turf(src), 'sound/items/Deconstruct.ogg', 50, 1)
		if(do_after(user, 50))
			if (prob(50) && electrocute_mob(usr, terminal.powernet, terminal))
				var/datum/effect/effect/system/spark_spread/s = new /datum/effect/effect/system/spark_spread
				s.set_up(5, 1, src)
				s.start()
				return
			new /obj/item/weapon/cable_coil(loc,10)
			user.visible_message(\
				"\red [user.name] cut the cables and dismantled the power terminal.",\
				"You cut the cables and dismantle the power terminal.")
			del(terminal)
	else if (istype(W, /obj/item/weapon/module/power_control) && opened && has_electronics==0 && !((stat & BROKEN) || malfhack))
		user << "You trying to insert the power control board into the frame..."
		playsound(get_turf(src), 'sound/items/Deconstruct.ogg', 50, 1)
		if(do_after(user, 10))
			has_electronics = 1
			user << "You place the power control board inside the frame."
			del(W)
	else if (istype(W, /obj/item/weapon/module/power_control) && opened && has_electronics==0 && ((stat & BROKEN) || malfhack))
		user << "\red You cannot put the board inside, the frame is damaged."
		return
	else if (istype(W, /obj/item/weapon/weldingtool) && opened && has_electronics==0 && !terminal)
		var/obj/item/weapon/weldingtool/WT = W
		if (WT.get_fuel() < 3)
			user << "\blue You need more welding fuel to complete this task."
			return
		user << "You start welding the APC frame..."
		playsound(get_turf(src), 'sound/items/Welder.ogg', 50, 1)
		if(do_after(user, 50))
			if(!src || !WT.remove_fuel(3, user)) return
			if (emagged || malfhack || (stat & BROKEN) || opened==2)
				new /obj/item/stack/sheet/metal(loc)
				user.visible_message(\
					"\red [src] has been cut apart by [user.name] with the weldingtool.",\
					"You disassembled the broken APC frame.",\
					"\red You hear welding.")
			else
				new /obj/item/mounted/frame/apc_frame(loc)
				user.visible_message(\
					"\red [src] has been cut from the wall by [user.name] with the weldingtool.",\
					"You cut the APC frame from the wall.",\
					"\red You hear welding.")
			del(src)
			return
	else if (istype(W, /obj/item/mounted/frame/apc_frame) && opened && emagged)
		emagged = 0
		if (opened==2)
			opened = 1
		user.visible_message(\
			"\red [user.name] has replaced the damaged APC frontal panel with a new one.",\
			"You replace the damaged APC frontal panel with a new one.")
		del(W)
		update_icon()
	else if (istype(W, /obj/item/mounted/frame/apc_frame) && opened && ((stat & BROKEN) || malfhack))
		if (has_electronics)
			user << "You cannot repair this APC until you remove the electronics still inside."
			return
		user << "You begin to replace the damaged APC frame..."
		if(do_after(user, 50))
			user.visible_message(\
				"\red [user.name] has replaced the damaged APC frame with new one.",\
				"You replace the damaged APC frame with new one.")
			del(W)
			stat &= ~BROKEN
			malfai = null
			malfhack = 0
			if (opened==2)
				opened = 1
			update_icon()
	else
		// The extra crowbar thing fixes MoMMIs not being able to remove APCs.
		// They can just pop them off with a crowbar.
		if (	((stat & BROKEN) || malfhack) \
				&& !opened \
				&& ( \
					(W.force >= 5 && W.w_class >= 3.0) \
					|| istype(W,/obj/item/weapon/crowbar) \
				) \
				&& prob(20) )
			opened = 2
			user.visible_message("\red The APC cover was knocked down with the [W.name] by [user.name]!", \
				"\red You knock down the APC cover with your [W.name]!", \
				"You hear bang")
			update_icon()
		else
			if (istype(user, /mob/living/silicon))
				return src.attack_hand(user)
			if (!opened && wiresexposed && \
				(istype(W, /obj/item/device/multitool) || \
				istype(W, /obj/item/weapon/wirecutters) || istype(W, /obj/item/device/assembly/signaler)))
				return src.attack_hand(user)
			user.visible_message("\red The [src.name] has been hit with the [W.name] by [user.name]!", \
				"\red You hit the [src.name] with your [W.name]!", \
				"You hear bang")

// attack with hand - remove cell (if cover open) or interact with the APC

/obj/machinery/power/apc/attack_hand(mob/user)
//	if (!can_use(user)) This already gets called in interact() and in topic()
//		return
	if(!user)
		return
	if(!isobserver(user))
		src.add_fingerprint(user)
		if(usr == user && opened)
			if(cell && get_dist(src,user)<=1)
				if(issilicon(user) && !isMoMMI(user)) // MoMMIs can hold one item in their tool slot.
					cell.loc=src.loc // Drop it, whoops.
				else
					user.put_in_hands(cell)

				cell.add_fingerprint(user)
				cell.updateicon()

				src.cell = null
				user.visible_message("\red [user.name] removes the power cell from [src.name]!", "You remove the power cell.")
				//user << "You remove the power cell."
				charging = 0
				src.update_icon()
			return
		if(stat & (BROKEN|MAINT))
			return

		if(ishuman(user))
			if(istype(user:gloves, /obj/item/clothing/gloves/space_ninja)&&user:gloves:candrain&&!user:gloves:draining)
				call(/obj/item/clothing/gloves/space_ninja/proc/drain)("APC",src,user:wear_suit)
				return
	// do APC interaction
	src.interact(user)

/obj/machinery/power/apc/attack_alien(mob/living/carbon/alien/humanoid/user)
	if(!user)
		return
	user.delayNextAttack(8)
	user.visible_message("\red [user.name] slashes at the [src.name]!", "\blue You slash at the [src.name]!")
	playsound(get_turf(src), 'sound/weapons/slash.ogg', 100, 1)

	var/allcut = wires.IsAllCut()

	if(beenhit >= pick(3, 4) && wiresexposed != 1)
		wiresexposed = 1
		src.update_icon()
		src.visible_message("\red The [src.name]'s cover flies open, exposing the wires!")

	else if(wiresexposed == 1 && allcut == 0)
		wires.CutAll()
		src.update_icon()
		src.visible_message("\red The [src.name]'s wires are shredded!")
	else
		beenhit += 1
	return


/obj/machinery/power/apc/interact(mob/user)
	if (!user)
		return

	if (wiresexposed)
		wires.Interact(user)

	if (stat & (BROKEN | MAINT | EMPED))
		return

	ui_interact(user)

/obj/machinery/power/apc/proc/get_malf_status(mob/user)
	if (ticker && ticker.mode && (user.mind in ticker.mode.malf_ai) && istype(user, /mob/living/silicon/ai))
		if (src.malfai == (user:parent ? user:parent : user))
			if (src.occupant == user)
				return 3 // 3 = User is shunted in this APC
			else if (istype(user.loc, /obj/machinery/power/apc))
				return 4 // 4 = User is shunted in another APC
			else
				return 2 // 2 = APC hacked by user, and user is in its core.
		else
			return 1 // 1 = APC not hacked.
	else
		return 0 // 0 = User is not a Malf AI

/obj/machinery/power/apc/ui_interact(mob/user, ui_key = "main", var/datum/nanoui/ui = null)
	if(!user)
		return

	var/list/data = list(
		"locked" = locked,
		"isOperating" = operating,
		"externalPower" = main_status,
		"powerCellStatus" = cell ? cell.percent() : null,
		"chargeMode" = chargemode,
		"chargingStatus" = charging,
		"totalLoad" = lastused_equip + lastused_light + lastused_environ,
		"coverLocked" = coverlocked,
		"siliconUser" = istype(user, /mob/living/silicon) || isAdminGhost(user), // Allow aghosts to fuck with APCs
		"malfStatus" = get_malf_status(user),

		"powerChannels" = list(
			list(
				"title" = "Equipment",
				"powerLoad" = lastused_equip,
				"status" = equipment,
				"topicParams" = list(
					"auto" = list("eqp" = 3),
					"on"   = list("eqp" = 2),
					"off"  = list("eqp" = 1)
				)
			),
			list(
				"title" = "Lighting",
				"powerLoad" = lastused_light,
				"status" = lighting,
				"topicParams" = list(
					"auto" = list("lgt" = 3),
					"on"   = list("lgt" = 2),
					"off"  = list("lgt" = 1)
				)
			),
			list(
				"title" = "Environment",
				"powerLoad" = lastused_environ,
				"status" = environ,
				"topicParams" = list(
					"auto" = list("env" = 3),
					"on"   = list("env" = 2),
					"off"  = list("env" = 1)
				)
			)
		)
	)

	// update the ui if it exists, returns null if no ui is passed/found
	ui = nanomanager.try_update_ui(user, src, ui_key, ui, data)
	if (!ui)
		// the ui does not exist, so we'll create a new one
        // for a list of parameters and their descriptions see the code docs in \code\modules\nano\nanoui.dm
		ui = new(user, src, ui_key, "apc.tmpl", "[areaMaster.name] - APC", 520, data["siliconUser"] ? 465 : 440)
		// when the ui is first opened this is the data it will use
		ui.set_initial_data(data)
		// open the new ui window
		ui.open()
		// auto update every Master Controller tick
		ui.set_auto_update(1)

/obj/machinery/power/apc/proc/report()
	return "[areaMaster.name] : [equipment]/[lighting]/[environ] ([lastused_equip+lastused_light+lastused_environ]) : [cell? cell.percent() : "N/C"] ([charging])"

/obj/machinery/power/apc/proc/update()
	if(operating && !shorted)
		areaMaster.power_light = (lighting > 1)
		areaMaster.power_equip = (equipment > 1)
		areaMaster.power_environ = (environ > 1)
//		if (area.name == "AI Chamber")
//			spawn(10)
//				world << " [area.name] [area.power_equip]"
	else
		areaMaster.power_light = 0
		areaMaster.power_equip = 0
		areaMaster.power_environ = 0
//		if (area.name == "AI Chamber")
//			world << "[area.power_equip]"
	areaMaster.power_change()

/obj/machinery/power/apc/proc/isWireCut(var/wireIndex)
	return wires.IsIndexCut(wireIndex)


/obj/machinery/power/apc/proc/can_use(mob/user as mob, var/loud = 0) //used by attack_hand() and Topic()
	if (user.stat && !isobserver(user))
		user << "\red You must be conscious to use this [src]!"
		return 0
	if(!user.client)
		return 0
	if ( ! (istype(user, /mob/living/carbon/human) || \
			istype(user, /mob/living/silicon) || \
			istype(user, /mob/dead/observer) || \
			istype(user, /mob/living/carbon/monkey) /*&& ticker && ticker.mode.name == "monkey"*/) )
		user << "\red You don't have the dexterity to use this [src]!"
		nanomanager.close_user_uis(user, src)

		return 0
	if(user.restrained())
		user << "\red You must have free hands to use this [src]"
		return 0
	if(user.lying)
		user << "\red You must stand to use this [src]!"
		return 0
	if (istype(user, /mob/living/silicon))
		var/mob/living/silicon/ai/AI = user
		var/mob/living/silicon/robot/robot = user
		if (                                                             \
			src.aidisabled ||                                            \
			malfhack && istype(malfai) &&                                \
			(                                                            \
				(istype(AI) && (malfai!=AI && malfai != AI.parent)) ||   \
				(istype(robot) && (robot in malfai.connected_robots))    \
			)                                                            \
		)
			if(!loud)
				user << "\red \The [src] have AI control disabled!"
				nanomanager.close_user_uis(user, src)

			return 0
	else if(isobserver(user))
		if(malfhack && istype(malfai) && !isAdminGhost(user))
			if(!loud)
				user << "\red \The [src] have AI control disabled!"
				nanomanager.close_user_uis(user, src)
			return 0
	else
		if ((!in_range(src, user) || !istype(src.loc, /turf)))
			nanomanager.close_user_uis(user, src)

			return 0

	var/mob/living/carbon/human/H = user
	if (istype(H))
		if(H.getBrainLoss() >= 60)
			for(var/mob/M in viewers(src, null))
				M << "\red [H] stares cluelessly at [src] and drools."
			return 0
		else if(prob(H.getBrainLoss()))
			user << "\red You momentarily forget how to use [src]."
			return 0
	return 1

/obj/machinery/power/apc/Topic(href, href_list)
	if(..())
		return 0

	if(!can_use(usr, 1))
		return 0

	if (href_list["lock"])
		coverlocked = !coverlocked

	else if (href_list["breaker"])
		toggle_breaker()

	else if (href_list["cmode"])
		chargemode = !chargemode
		if(!chargemode)
			charging = 0
			update_icon()

	else if (href_list["eqp"])
		var/val = text2num(href_list["eqp"])
		equipment = setsubsystem(val)
		update_icon()
		update()

	else if (href_list["lgt"])
		var/val = text2num(href_list["lgt"])
		lighting = setsubsystem(val)
		update_icon()
		update()

	else if (href_list["env"])
		var/val = text2num(href_list["env"])
		environ = setsubsystem(val)
		update_icon()
		update()

	else if (href_list["overload"])
		if(istype(usr, /mob/living/silicon))
			src.overload_lighting()

	else if (href_list["malfhack"])
		var/mob/living/silicon/ai/malfai = usr
		if(get_malf_status(malfai)==1)
			if (malfai.malfhacking)
				malfai << "You are already hacking an APC."
				return 1
			malfai << "Beginning override of APC systems. This takes some time, and you cannot perform other actions during the process."
			malfai.malfhack = src
			malfai.malfhacking = 1
			sleep(600)
			if(src)
				if (!src.aidisabled)
					malfai.malfhack = null
					malfai.malfhacking = 0
					locked = 1
					if (ticker.mode.config_tag == "malfunction")
						if (STATION_Z == z)
							ticker.mode:apcs++
					if(usr:parent)
						src.malfai = usr:parent
					else
						src.malfai = usr
					malfai << "Hack complete. The APC is now under your exclusive control."
					update_icon()

	else if (href_list["occupyapc"])
		if(get_malf_status(usr))
			malfoccupy(usr)

	else if (href_list["deoccupyapc"])
		if(get_malf_status(usr))
			malfvacate()

	else if (href_list["toggleaccess"])
		if(istype(usr, /mob/living/silicon))
			if(emagged || (stat & (BROKEN|MAINT)))
				usr << "The APC does not respond to the command."
			else
				locked = !locked
				update_icon()

	return 1

/obj/machinery/power/apc/proc/toggle_breaker()
	operating = !operating

	if(malfai)
		if (ticker.mode.config_tag == "malfunction")
			if (STATION_Z == z)
				operating ? ticker.mode:apcs++ : ticker.mode:apcs--

	src.update()
	update_icon()

/obj/machinery/power/apc/proc/malfoccupy(var/mob/living/silicon/ai/malf)
	if(!istype(malf))
		return
	if(istype(malf.loc, /obj/machinery/power/apc)) // Already in an APC
		malf << "<span class='warning'>You must evacuate your current apc first.</span>"
		return
	if(!malf.can_shunt)
		malf << "<span class='warning'>You cannot shunt.</span>"
		return
	if(STATION_Z != z)
		return
	src.occupant = new /mob/living/silicon/ai(src,malf.laws,null,1)
	src.occupant.adjustOxyLoss(malf.getOxyLoss())
	if(!findtext(src.occupant.name,"APC Copy"))
		src.occupant.name = "[malf.name] APC Copy"
	if(malf.parent)
		src.occupant.parent = malf.parent
	else
		src.occupant.parent = malf
	malf.mind.transfer_to(src.occupant)
	src.occupant.eyeobj.name = "[src.occupant.name] (AI Eye)"
	if(malf.parent)
		del(malf)
	src.occupant.verbs += /mob/living/silicon/ai/proc/corereturn
	src.occupant.verbs += /datum/game_mode/malfunction/proc/takeover
	src.occupant.cancel_camera()
	if (seclevel2num(get_security_level()) == SEC_LEVEL_DELTA)
		for(var/obj/item/weapon/pinpointer/point in world)
			point.the_disk = src //the pinpointer will detect the shunted AI


/obj/machinery/power/apc/proc/malfvacate(var/forced)
	if(!src.occupant)
		return
	if(src.occupant.parent && src.occupant.parent.stat != 2)
		src.occupant.mind.transfer_to(src.occupant.parent)
		src.occupant.parent.adjustOxyLoss(src.occupant.getOxyLoss())
		src.occupant.parent.cancel_camera()
		del(src.occupant)
		if (seclevel2num(get_security_level()) == SEC_LEVEL_DELTA)
			for(var/obj/item/weapon/pinpointer/point in world)
				for(var/datum/mind/AI_mind in ticker.mode.malf_ai)
					var/mob/living/silicon/ai/A = AI_mind.current // the current mob the mind owns
					if(A.stat != DEAD)
						point.the_disk = A //The pinpointer tracks the AI back into its core.

	else
		src.occupant << "\red Primary core damaged, unable to return core processes."
		if(forced)
			src.occupant.loc = src.loc
			src.occupant.death()
			src.occupant.gib()
			for(var/obj/item/weapon/pinpointer/point in world)
				point.the_disk = null //the pinpointer will go back to pointing at the nuke disc.


/obj/machinery/power/apc/proc/ion_act()
	//intended to be exactly the same as an AI malf attack
	if(!src.malfhack && STATION_Z == z)
		if(prob(3))
			src.locked = 1
			if (src.cell.charge > 0)
//				world << "\red blew APC in [src.loc.loc]"
				src.cell.charge = 0
				cell.corrupt()
				src.malfhack = 1
				update_icon()
				var/datum/effect/effect/system/smoke_spread/smoke = new /datum/effect/effect/system/smoke_spread()
				smoke.set_up(3, 0, src.loc)
				smoke.attach(src)
				smoke.start()
				var/datum/effect/effect/system/spark_spread/s = new /datum/effect/effect/system/spark_spread
				s.set_up(3, 1, src)
				s.start()
				for(var/mob/M in viewers(src))
					M.show_message("\red The [src.name] suddenly lets out a blast of smoke and some sparks!", 3, "\red You hear sizzling electronics.", 2)


/obj/machinery/power/apc/surplus()
	if(terminal)
		return terminal.surplus()
	else
		return 0

/obj/machinery/power/apc/add_load(var/amount)
	if(terminal && terminal.powernet)
		terminal.powernet.load += amount

/obj/machinery/power/apc/avail()
	if(terminal)
		return terminal.avail()
	else
		return 0

/obj/machinery/power/apc/process()

	if(stat & (BROKEN|MAINT))
		return
	if(!areaMaster.requires_power)
		return

	/*
	if (equipment > 1) // off=0, off auto=1, on=2, on auto=3
		use_power(src.equip_consumption, EQUIP)
	if (lighting > 1) // off=0, off auto=1, on=2, on auto=3
		use_power(src.light_consumption, LIGHT)
	if (environ > 1) // off=0, off auto=1, on=2, on auto=3
		use_power(src.environ_consumption, ENVIRON)

	area.calc_lighting() */

	lastused_light = areaMaster.usage(LIGHT)
	lastused_light += areaMaster.usage(STATIC_LIGHT)
	lastused_equip = areaMaster.usage(EQUIP)
	lastused_light += areaMaster.usage(STATIC_EQUIP)
	lastused_environ = areaMaster.usage(ENVIRON)
	lastused_light += areaMaster.usage(STATIC_ENVIRON)
	areaMaster.clear_usage()

	lastused_total = lastused_light + lastused_equip + lastused_environ

	//store states to update icon if any change
	var/last_lt = lighting
	var/last_eq = equipment
	var/last_en = environ
	var/last_ch = charging

	var/excess = surplus()

	if(!src.avail())
		main_status = 0
	else if(excess < 0)
		main_status = 1
	else
		main_status = 2

	//if(debug)
	//	world.log << "Status: [main_status] - Excess: [excess] - Last Equip: [lastused_equip] - Last Light: [lastused_light] - Longterm: [longtermpower]"

	if(cell && !shorted)

		// draw power from cell as before to power the area
		var/cellused = min(cell.charge, CELLRATE * lastused_total)	// clamp deduction to a max, amount left in cell
		cell.use(cellused)

		if(excess > lastused_total) // if power excess recharge the cell
									// by the same amount just used
			cell.give(cellused)
			add_load(cellused/CELLRATE)		// add the load used to recharge the cell


		else		// no excess, and not enough per-apc

			if((cell.charge / CELLRATE + excess) >= lastused_total)					// can we draw enough from cell+grid to cover last usage?
				cell.charge = min(cell.maxcharge, cell.charge + CELLRATE * excess)	//recharge with what we can
				add_load(excess)		// so draw what we can from the grid
				charging = 0

			else	// not enough power available to run the last tick!
				charging = 0
				chargecount = 0
				// This turns everything off in the case that there is still a charge left on the battery, just not enough to run the room.
				equipment = autoset(equipment, 0)
				lighting = autoset(lighting, 0)
				environ = autoset(environ, 0)


		// set channels depending on how much charge we have left

		// Allow the APC to operate as normal if the cell can charge
		if(charging && longtermpower < 10)
			longtermpower += 1
		else if(longtermpower > -10)
			longtermpower -= 2

		if(cell.charge <= 0)					// zero charge, turn all off
			equipment = autoset(equipment, 0)
			lighting = autoset(lighting, 0)
			environ = autoset(environ, 0)
			areaMaster.poweralert(0, src)
		else if(cell.percent() < 15 && longtermpower < 0)	// <15%, turn off lighting & equipment
			equipment = autoset(equipment, 2)
			lighting = autoset(lighting, 2)
			environ = autoset(environ, 1)
			areaMaster.poweralert(0, src)
		else if(cell.percent() < 30 && longtermpower < 0)			// <30%, turn off equipment
			equipment = autoset(equipment, 2)
			lighting = autoset(lighting, 1)
			environ = autoset(environ, 1)
			areaMaster.poweralert(0, src)
		else									// otherwise all can be on
			equipment = autoset(equipment, 1)
			lighting = autoset(lighting, 1)
			environ = autoset(environ, 1)
			areaMaster.poweralert(1, src)
			if(cell.percent() > 75)
				areaMaster.poweralert(1, src)

		// now trickle-charge the cell

		if(chargemode && charging == 1 && operating)
			if(excess > 0)		// check to make sure we have enough to charge
				// Max charge is capped to % per second constant
				var/ch = min(excess * CELLRATE, cell.maxcharge * CHARGELEVEL)
				add_load(ch/CELLRATE) // Removes the power we're taking from the grid
				cell.give(ch) // actually recharge the cell

			else
				charging = 0		// stop charging
				chargecount = 0

		// show cell as fully charged if so
		if(cell.charge >= cell.maxcharge)
			cell.charge = cell.maxcharge
			charging = 2

		if(chargemode)
			if(!charging)
				if(excess > cell.maxcharge*CHARGELEVEL)
					chargecount++
				else
					chargecount = 0
					charging = 0

				if(chargecount == 10)

					chargecount = 0
					charging = 1

		else // chargemode off
			charging = 0
			chargecount = 0

	else // no cell, switch everything off

		charging = 0
		chargecount = 0
		equipment = autoset(equipment, 0)
		lighting = autoset(lighting, 0)
		environ = autoset(environ, 0)
		areaMaster.poweralert(0, src)

	// update icon & area power if anything changed
	if(last_lt != lighting || last_eq != equipment || last_en != environ)
		queue_icon_update()
		update()
	else if (last_ch != charging)
		queue_icon_update()

// val 0=off, 1=off(auto) 2=on 3=on(auto)
// on 0=off, 1=on, 2=autooff

obj/machinery/power/apc/proc/autoset(var/val, var/on)
	if(on==0)
		if(val==2)			// if on, return off
			return 0
		else if(val==3)		// if auto-on, return auto-off
			return 1

	else if(on==1)
		if(val==1)			// if auto-off, return auto-on
			return 3

	else if(on==2)
		if(val==3)			// if auto-on, return auto-off
			return 1

	return val

// damage and destruction acts

/obj/machinery/power/apc/meteorhit(var/obj/O as obj)

	set_broken()
	return

/obj/machinery/power/apc/emp_act(severity)
	if(cell)
		cell.emp_act(severity)
	if(occupant)
		occupant.emp_act(severity)
	lighting = 0
	equipment = 0
	environ = 0
	spawn(600)
		equipment = 3
		environ = 3
	..()

/obj/machinery/power/apc/ex_act(severity)

	switch(severity)
		if(1.0)
			//set_broken() //now Destroy() do what we need
			if (cell)
				cell.ex_act(1.0) // more lags woohoo
			qdel(src)
			return
		if(2.0)
			if (prob(50))
				set_broken()
				if (cell && prob(50))
					cell.ex_act(2.0)
		if(3.0)
			if (prob(25))
				set_broken()
				if (cell && prob(25))
					cell.ex_act(3.0)
	return

/obj/machinery/power/apc/blob_act()
	if (prob(75))
		set_broken()
		if (cell && prob(5))
			cell.blob_act()

/obj/machinery/power/apc/proc/set_broken()
	if(malfai && operating)
		if (ticker.mode.config_tag == "malfunction")
			if (STATION_Z == z)
				ticker.mode:apcs--
	stat |= BROKEN
	operating = 0
	if(occupant)
		malfvacate(1)
	update_icon()
	update()

// overload all the lights in this APC area

/obj/machinery/power/apc/proc/overload_lighting()
	if(/* !get_connection() || */ !operating || shorted)
		return
	if( cell && cell.charge>=20)
		cell.use(20);
		spawn(0)
			for(var/area/A in areaMaster.related)
				for(var/obj/machinery/light/L in A)
					L.on = 1
					L.broken()
					sleep(1)

/obj/machinery/power/apc/Destroy()
	if(malfai && operating)
		if (ticker.mode.config_tag == "malfunction")
			if (STATION_Z == z)
				ticker.mode:apcs--
	areaMaster.power_light = 0
	areaMaster.power_equip = 0
	areaMaster.power_environ = 0
	areaMaster.power_change()
	if(occupant)
		malfvacate(1)

	if(cell)
		cell.loc = loc
		cell = null

	if(terminal)
		terminal.master = null
		terminal = null

	if(wires)
		wires.Destroy()
		wires = null

	..()

/obj/machinery/power/apc/proc/setsubsystem(val)
	if(cell && cell.charge > 0)
		return (val==1) ? 0 : val
	else if(val == 3)
		return 1
	else
		return 0

#undef APC_UPDATE_ICON_COOLDOWN
