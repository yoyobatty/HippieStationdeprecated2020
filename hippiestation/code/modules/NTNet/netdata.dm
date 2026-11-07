// Process data before sending it
/datum/netdata/proc/pre_send(datum/component/ntnet_interface/interface)
	// Decrypt the passkey.
	if(autopasskey)
		if(data["encrypted_passkey"] && !passkey)
			var/result = XorEncrypt(hextostr(data["encrypted_passkey"], TRUE), SScircuit.cipherkey)
			if(length(result) > 1)
				try
					passkey = json_decode(result) // a passkey typed in by hand decrypts to junk, which throws
				catch
					passkey = null

		// Encrypt the passkey. (This sat inside the decrypt branch above, whose condition is its opposite, so it never ran.)
		if(!data["encrypted_passkey"] && passkey)
			data["encrypted_passkey"] = strtohex(XorEncrypt(json_encode(passkey), SScircuit.cipherkey))

	// If there is no sender ID, set the default one.
	if(!sender_id && interface)
		sender_id = interface.hardware_id

/datum/component/ntnet_interface/__network_send(datum/netdata/data, netid)
	// Process data before sending it
	data.pre_send(src)
	return(..(data,netid))
