.in:
	if sed \
		-e 's#[@]datarootdir_POST[@]#$(datarootdir)#g' \
		-e 's#[@]localstatedir_POST[@]#$(localstatedir)#g' \
		-e 's#[@]sysconfdir_POST[@]#$(sysconfdir)#g' \
		$< > $@.tmp; then \
		mv "$@.tmp" "$@"; \
	else \
		rm -f "$@.tmp"; \
		false; \
	fi
