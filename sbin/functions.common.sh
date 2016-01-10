#
#   Copyright
#
#       Copyright (C) 2003-2014 Costa Tsaousis <costa@tsaousis.gr>
#       Copyright (C) 2012-2014 Phil Whineray <phil@sanewall.org>
#
#   See sbin/firehol.in for details
#
#   This file contains functions used by the firehol suite.
#   To keep the namespace clean, functions defined in functions.x.sh
#   should be of the form x_whatever() if they are intended for general
#   use or int_x_whatever() if they are intended as helpers to the other
#   functions in the file.
#

which_cmd() {
	local name="$1"
	shift

	if [ "$1" = ":" ]
	then
		eval $name=":"
		return 0
	fi

	unalias $1 >/dev/null 2>&1
	local cmd=
	IFS= read cmd <<-EOF
	$(which $1 2> /dev/null)
	EOF

	if [ $? -gt 0 -o ! -x "${cmd}" ]
	then
		return 1
	fi
	shift

	if [ $# -eq 0 ]
	then
		eval $name="'${cmd}'"
	else
		eval $name="'${cmd} ${@}'"
	fi
	return 0
}

common_require_cmd() {
	local progname= var= val= block=1

	progname="$1"
	shift

	if [ "$1" = "-n" ]
	then
		block=0
		shift
	fi

	var="$1"
	shift

	eval val=\$\{${var}\} || return 2
	if [ "${val}" ]
	then
		local cmd="${val/ */}"
		if [ "$cmd" != ":" -a ! -x "$cmd" ]
		then
			echo >&2
			if [ $block -eq 0 ]
			then
				echo >&2 "WARNING: optional command does not exist or is not executable ($cmd)"
				echo >&2 "please add or correct $var in firehol-defaults.conf"
				val=""
			else
				echo >&2 "ERROR: required command does not exist or is not executable ($cmd)"
				echo >&2 "please add or correct $var in firehol-defaults.conf"
				return 2
			fi
		fi

		# link-balancer calls itself; export our findings so
		# we do not repeat all of the lookups
		eval export "$var"
		return 0
	elif [ $block -eq 0 ]
	then
		eval set -- "$@"
		for cmd in "$@"
		do
			eval "NEED_${var}"="\$NEED_${var}' ${cmd/ */}'"
		done
		return 0
	fi

	if [ $# -eq 0 ]
	then
		eval set -- "\$NEED_${var}"
	fi

	echo >&2
	echo >&2 "ERROR:	$progname REQUIRES ONE OF THESE COMMANDS:"
	echo >&2
	echo >&2 "	${@}"
	echo >&2
	echo >&2 "	You have requested the use of a $progname"
	echo >&2 "	feature that requires certain external programs"
	echo >&2 "	to be installed in the running system."
	echo >&2
	echo >&2 "	Please consult your Linux distribution manual to"
	echo >&2 "	install the package(s) that provide these external"
	echo >&2 "	programs and retry."
	echo >&2
	echo >&2 "	Note that you need an operational 'which' command"
	echo >&2 "	for $progname to find all the external programs it"
	echo >&2 "	needs. Check it yourself. Run:"
	echo >&2
	for x in "${@}"
	do
		echo >&2 "	which $x"
	done

	return 2
}

int_common_which_all() {
	local cmd_var="$1"

	eval set -- "$2"
	for cmd in "$@"
	do
		which_cmd $cmd_var $cmd && break
	done
}

# Where required = Y, if a command is not found, FireHOL will refuse to run.
# Where required = N, the command only required when it is actually used
#
# If a command is specified in /etc/firehol/firehol-defaults.conf it will
# be used. Otherwise, if the script has been configured with ./configure
# the detected versions will be used. If the script has not been configured
# then the list of possible commands is autodetected.
common_load_commands() {
	local progname="$1"
	shift
	local AUTOCONF_RUN="$1"
	shift

	while IFS="|" read required cmd_var autoconf possibles
	do
		if [ "$AUTOCONF_RUN" = "Y" ]
		then
			case "$autoconf" in
				"@"*) autoconf=""; ;;
			esac
		fi
		eval set_in_defaults=\"\$$cmd_var\"
		if [ "$set_in_defaults" ]
		then
			:
		elif [ "$AUTOCONF_RUN" = "Y" -a ! -z "$autoconf" ]
		then
			eval $cmd_var=\"$autoconf\"
		else
			dirname="${0%/*}"
			if [ "$dirname" = "$0" ]; then dirname="."; fi
			PATH="/bin:/usr/bin:/sbin:/usr/sbin:/usr/local/bin:/usr/local/sbin:$PATH:$dirname" int_common_which_all $cmd_var "$possibles"
		fi
		if [ "$required" = "Y" ]
		then
			common_require_cmd $progname $cmd_var $possibles || return
		else
			common_require_cmd $progname -n $cmd_var $possibles || return
		fi
	done
}

common_require_root() {
	if [ "${UID}" != 0 ]
	then
		echo >&2
		echo >&2 "ERROR:"
		echo >&2 "Only user root can run ${1}"
		echo >&2
		return 1
	fi
	return 0
}

common_disable_localization() {
	export LC_ALL=C
}

common_private_umask() {
	# Make sure our generated files cannot be accessed by anyone else.
	umask 077
}

common_public_umask() {
	# let everyone read our status info
	umask 022
}

common_setup_terminal() {
	# Are stdout/stderr on the terminal? If not, then fail
	test -t 2 || return 1
	test -t 1 || return 1

	if [ ! -z "$TPUT_CMD" ]
	then
		if [ $[$($TPUT_CMD colors 2>/dev/null)] -ge 8 ]
		then
			# Enable colors
			COLOR_RESET="\e[0m"
			COLOR_BLACK="\e[30m"
			COLOR_RED="\e[31m"
			COLOR_GREEN="\e[32m"
			COLOR_YELLOW="\e[33m"
			COLOR_BLUE="\e[34m"
			COLOR_PURPLE="\e[35m"
			COLOR_CYAN="\e[36m"
			COLOR_WHITE="\e[37m"
			COLOR_BGBLACK="\e[40m"
			COLOR_BGRED="\e[41m"
			COLOR_BGGREEN="\e[42m"
			COLOR_BGYELLOW="\e[43m"
			COLOR_BGBLUE="\e[44m"
			COLOR_BGPURPLE="\e[45m"
			COLOR_BGCYAN="\e[46m"
			COLOR_BGWHITE="\e[47m"
			COLOR_BOLD="\e[1m"
			COLOR_DIM="\e[2m"
			COLOR_UNDERLINED="\e[4m"
			COLOR_BLINK="\e[5m"
			COLOR_INVERTED="\e[7m"
		fi
	fi

	return 0
}
