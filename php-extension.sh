#!/bin/sh

# This script wraps docker-php-ext-install, properly configuring the system.
#
# Copyright (c) Michele Locati, 2018-2021
#
# Source: https://github.com/mlocati/docker-php-extension-installer
#
# License: MIT - see https://github.com/mlocati/docker-php-extension-installer/blob/master/LICENSE

# Let's set a sane environment
set -o errexit
set -o nounset

if ! which docker-php-ext-configure >/dev/null || ! which docker-php-ext-enable >/dev/null || ! which docker-php-ext-install >/dev/null || ! which docker-php-source >/dev/null; then
	printf 'The script %s is meant to be used with official Docker PHP Images - https://hub.docker.com/_/php\n' "$0" >&2
	exit 1
fi

IPE_VERSION=1.2.28

if test "$IPE_VERSION" = master && test "${CI:-}" != true; then
	cat <<EOF

#############################################################################################################
#                                                                                                           #
#                                            W A R N I N G ! ! !                                            #
#                                                                                                           #
# You are using an unsupported method to get install-php-extensions!                                        #
#                                                                                                           #
# Please update the way you fetch it. Read the instructions at                                              #
# https://github.com/mlocati/docker-php-extension-installer#usage                                           #
#                                                                                                           #
# For example, if you get this script by fetching                                                           #
# https://raw.githubusercontent.com/mlocati/docker-php-extension-installer/master/install-php-extensions    #
# replace it with                                                                                           #
# https://github.com/mlocati/docker-php-extension-installer/releases/latest/download/install-php-extensions #
#                                                                                                           #
# Sleeping for a while so you get bored of this and act ;)                                                  #
#                                                                                                           #
#############################################################################################################

EOF
	sleep 10 || true
else
	printf 'install-php-extensions v.%s\n' "$IPE_VERSION"
fi

# Reset the Internal Field Separator
resetIFS() {
	IFS='	 
'
}

# Set these variables:
# - DISTRO containing distribution name (eg 'alpine', 'debian')
# - DISTO_VERSION containing distribution name and its version(eg 'alpine@3.10', 'debian@9')
setDistro() {
	if ! test -r /etc/os-release; then
		printf 'The file /etc/os-release is not readable\n' >&2
		exit 1
	fi
	DISTRO="$(cat /etc/os-release | grep -E ^ID= | cut -d = -f 2)"
	DISTRO_VERSION_NUMBER="$(cat /etc/os-release | grep -E ^VERSION_ID= | cut -d = -f 2 | cut -d '"' -f 2 | cut -d . -f 1,2)"
	DISTRO_VERSION="$(printf '%s@%s' $DISTRO $DISTRO_VERSION_NUMBER)"
	DISTRO_MAJMIN_VERSION="$(echo "$DISTRO_VERSION_NUMBER" | awk -F. '{print $1*100+$2}')"
}

# Set:
# - PHP_MAJMIN_VERSION: Major-Minor version, format MMmm (example 800 for PHP 8.0.1)
# - PHP_MAJMINPAT_VERSION: Major-Minor-Patch version, format MMmmpp (example 80001 for PHP 8.0.1) variables containing integers value
setPHPVersionVariables() {
	setPHPVersionVariables_textual="$(php-config --version)"
	PHP_MAJMIN_VERSION=$(printf '%s' "$setPHPVersionVariables_textual" | awk -F. '{print $1*100+$2}')
	PHP_MAJMINPAT_VERSION=$(printf '%s' "$setPHPVersionVariables_textual" | awk -F. '{print $1*10000+$2*100+$3}')
}

# Fix apt-get being very slow on Debian Jessie
# See https://bugs.launchpad.net/ubuntu/+source/apt/+bug/1332440
fixMaxOpenFiles() {
	fixMaxOpenFiles_cur=$(ulimit -n 2>/dev/null || echo 0)
	if test "$fixMaxOpenFiles_cur" -gt 10000; then
		ulimit -n 10000
	fi
}

# Get the directory containing the compiled PHP extensions
#
# Output:
#   The absolute path of the extensions dir
getPHPExtensionsDir() {
	php -i | grep -E '^extension_dir' | head -n1 | tr -s '[:space:]*=>[:space:]*' '|' | cut -d'|' -f2
}

# Normalize the name of a PHP extension
#
# Arguments:
#   $1: the name of the module to be normalized
#
# Output:
#   The normalized module name
normalizePHPModuleName() {
	normalizePHPModuleName_name="$1"
	case "$normalizePHPModuleName_name" in
		*A* | *B* | *C* | *D* | *E* | *F* | *G* | *H* | *I* | *J* | *K* | *L* | *M* | *N* | *O* | *P* | *Q* | *R* | *S* | *T* | *U* | *V* | *W* | *X* | *Y* | *Z*)
			normalizePHPModuleName_name="$(LC_CTYPE=C printf '%s' "$normalizePHPModuleName_name" | tr '[:upper:]' '[:lower:]')"
			;;
	esac
	case "$normalizePHPModuleName_name" in
		ioncube | ioncube\ loader)
			normalizePHPModuleName_name='ioncube_loader'
			;;
		pecl_http)
			normalizePHPModuleName_name='http'
			;;
		zend\ opcache)
			normalizePHPModuleName_name='opcache'
			;;
		*\ *)
			printf '### WARNING Unrecognized module name: %s ###\n' "$1" >&2
			;;
	esac
	printf '%s' "$normalizePHPModuleName_name"
}

# Get the PECL name of PHP extension
#
# Arguments:
#   $1: the name of the extension
#
# Output:
#   The PECL name of the extension
getPeclModuleName() {
	normalizePHPModuleName_name="$1"
	case "$normalizePHPModuleName_name" in
		http)
			normalizePHPModuleName_name=pecl_http
			;;
	esac
	printf '%s' "$normalizePHPModuleName_name"
}

# Parse a module name (and optionally version) as received via command arguments, extracting the version and normalizing it
# Examples:
#   xdebug-2.9.8
#   xdebug-^2
#   xdebug-^2.9
#
# Arguments:
#   $1: the name of the module to be normalized
#
# Set these variables:
# - PROCESSED_PHP_MODULE_ARGUMENT
#
# Optionally set these variables:
# - PHP_WANTEDMODULEVERSION_<...> (where <...> is the normalized module name)
#
# Output:
#   Nothing
processPHPMuduleArgument() {
	PROCESSED_PHP_MODULE_ARGUMENT="${1%%-*}"
	if test -n "$PROCESSED_PHP_MODULE_ARGUMENT" && test "$PROCESSED_PHP_MODULE_ARGUMENT" != "$1"; then
		processPHPMuduleArgument_version="${1#*-}"
	else
		processPHPMuduleArgument_version=''
	fi
	PROCESSED_PHP_MODULE_ARGUMENT="$(normalizePHPModuleName "$PROCESSED_PHP_MODULE_ARGUMENT")"
	if test -n "$processPHPMuduleArgument_version"; then
		if printf '%s' "$PROCESSED_PHP_MODULE_ARGUMENT" | grep -Eq '^[a-zA-Z0-9_]+$'; then
			eval PHP_WANTEDMODULEVERSION_$PROCESSED_PHP_MODULE_ARGUMENT="$processPHPMuduleArgument_version"
		elif printf '%s' "$PROCESSED_PHP_MODULE_ARGUMENT" | grep -Eq '^@[a-zA-Z0-9_]+$'; then
			eval PHP_WANTEDMODULEVERSION__${PROCESSED_PHP_MODULE_ARGUMENT#@}="$processPHPMuduleArgument_version"
		else
			printf 'Unable to parse the following module name:\n%s\n' "$PROCESSED_PHP_MODULE_ARGUMENT" >&2
		fi
	fi
}

# Get the wanted PHP module version, as specified in the command line arguments.
#
# Arguments:
#   $1: the name of the module to be normalized
#
# Output:
#   The wanted version (if any)
getWantedPHPModuleVersion() {
	if printf '%s' "$1" | grep -Eq '^[a-zA-Z0-9_]+$'; then
		eval printf '%s' "\${PHP_WANTEDMODULEVERSION_$1:-}"
	elif printf '%s' "$1" | grep -Eq '^@[a-zA-Z0-9_]+$'; then
		eval printf '%s' "\${PHP_WANTEDMODULEVERSION__${1#@}:-}"
	fi
}

# Get the wanted PHP module version, resolving it if it starts with '^'
#
# Arguments:
#   $1: the name of the module to be normalized
#
# Output:
#   The version to be used
resolveWantedPHPModuleVersion() {
	resolveWantedPHPModuleVersion_raw="$(getWantedPHPModuleVersion "$1")"
	resolveWantedPHPModuleVersion_afterCaret="${resolveWantedPHPModuleVersion_raw#^}"
	if test "$resolveWantedPHPModuleVersion_raw" = "$resolveWantedPHPModuleVersion_afterCaret"; then
		printf '%s' "$resolveWantedPHPModuleVersion_raw"
		return
	fi
	resolveWantedPHPModuleVersion_xml="$(curl -sSLf "http://pecl.php.net/rest/r/$1/allreleases.xml")"
	resolveWantedPHPModuleVersion_versions="$(printf '%s' "$resolveWantedPHPModuleVersion_xml" | tr -s ' \t\r\n' ' ' | sed -r 's# *<#\n<#g' | grep '<v>' | sed 's#<v>##g' | sed 's# ##g')"
	resetIFS
	for resolveWantedPHPModuleVersion_version in $resolveWantedPHPModuleVersion_versions; do
		resolveWantedPHPModuleVersion_suffix="${resolveWantedPHPModuleVersion_version#$resolveWantedPHPModuleVersion_afterCaret}"
		if test "$resolveWantedPHPModuleVersion_version" != "${resolveWantedPHPModuleVersion_version#$resolveWantedPHPModuleVersion_afterCaret.}"; then
			# Example: looking for 1.0, found 1.0.1
			printf '%s' "$resolveWantedPHPModuleVersion_version"
			return
		fi
	done
	for resolveWantedPHPModuleVersion_version in $resolveWantedPHPModuleVersion_versions; do
		resolveWantedPHPModuleVersion_suffix="${resolveWantedPHPModuleVersion_version#$resolveWantedPHPModuleVersion_afterCaret}"
		if test "$resolveWantedPHPModuleVersion_version" = "$resolveWantedPHPModuleVersion_suffix"; then
			continue
		fi
		if test -z "$resolveWantedPHPModuleVersion_suffix"; then
			# Example: looking for 1.0, found exactly it
			printf '%s' "$resolveWantedPHPModuleVersion_version"
			return
		fi
		case "$resolveWantedPHPModuleVersion_suffix" in
			[0-9])
				# Example: looking for 1.1, but this is 1.10
				;;
			*)
				# Example: looking for 1.1, this is 1.1rc1
				printf '%s' "$resolveWantedPHPModuleVersion_version"
				return
				;;
		esac
	done
	printf 'Unable to find a version of "%s" compatible with "%s"\nAvailable versions are:\n%s\n' "$1" "$resolveWantedPHPModuleVersion_raw" "$resolveWantedPHPModuleVersion_versions" >&2
	exit 1
}

# Set these variables:
# - PHP_PREINSTALLED_MODULES the normalized list of PHP modules installed before running this script
setPHPPreinstalledModules() {
	PHP_PREINSTALLED_MODULES=''
	IFS='
'
	for getPHPInstalledModules_module in $(php -m); do
		getPHPInstalledModules_moduleNormalized=''
		case "$getPHPInstalledModules_module" in
			\[PHP\ Modules\]) ;;
			\[Zend\ Modules\])
				break
				;;
			*)
				getPHPInstalledModules_moduleNormalized="$(normalizePHPModuleName "$getPHPInstalledModules_module")"
				if ! stringInList "$getPHPInstalledModules_moduleNormalized" "$PHP_PREINSTALLED_MODULES"; then
					PHP_PREINSTALLED_MODULES="$PHP_PREINSTALLED_MODULES $getPHPInstalledModules_moduleNormalized"
				fi
				;;
		esac
	done
	if command -v composer >/dev/null; then
		PHP_PREINSTALLED_MODULES="$PHP_PREINSTALLED_MODULES @composer"
	fi
	resetIFS
	PHP_PREINSTALLED_MODULES="${PHP_PREINSTALLED_MODULES# }"
}

# Get the handles of the modules to be installed
#
# Arguments:
#   $@: all module handles
#
# Set:
#   PHP_MODULES_TO_INSTALL
#
# Output:
#   Nothing
processCommandArguments() {
	processCommandArguments_endArgs=0
	PHP_MODULES_TO_INSTALL=''
	while :; do
		if test $# -lt 1; then
			break
		fi
		processCommandArguments_skip=0
		if test $processCommandArguments_endArgs -eq 0; then
			case "$1" in
				--cleanup)
					printf '### WARNING the %s option is deprecated (we always cleanup everything) ###\n' "$1" >&2
					processCommandArguments_skip=1
					;;
				--)
					processCommandArguments_skip=1
					processCommandArguments_endArgs=1
					;;
				-*)
					printf 'Unrecognized option: %s\n' "$1" >&2
					exit 1
					;;
			esac
		fi
		if test $processCommandArguments_skip -eq 0; then
			processPHPMuduleArgument "$1"
			processCommandArguments_name="$PROCESSED_PHP_MODULE_ARGUMENT"
			if stringInList "$processCommandArguments_name" "$PHP_MODULES_TO_INSTALL"; then
				printf '### WARNING Duplicated module name specified: %s ###\n' "$processCommandArguments_name" >&2
			elif stringInList "$processCommandArguments_name" "$PHP_PREINSTALLED_MODULES"; then
				printf '### WARNING Module already installed: %s ###\n' "$processCommandArguments_name" >&2
			else
				PHP_MODULES_TO_INSTALL="$PHP_MODULES_TO_INSTALL $processCommandArguments_name"
			fi
		fi
		shift
	done
	PHP_MODULES_TO_INSTALL="${PHP_MODULES_TO_INSTALL# }"
}

# Add a module that's required by another module
#
# Arguments:
#   $1: module that requires another module
#   $2: the required module
#
# Update:
#   PHP_MODULES_TO_INSTALL
#
# Output:
#   Nothing
checkRequiredModule() {
	if ! stringInList "$1" "$PHP_MODULES_TO_INSTALL"; then
		return
	fi
	if stringInList "$2" "$PHP_PREINSTALLED_MODULES"; then
		return
	fi
	PHP_MODULES_TO_INSTALL="$(removeStringFromList "$1" "$PHP_MODULES_TO_INSTALL")"
	if ! stringInList "$2" "$PHP_MODULES_TO_INSTALL"; then
		PHP_MODULES_TO_INSTALL="$PHP_MODULES_TO_INSTALL $2"
		PHP_MODULES_TO_INSTALL="${PHP_MODULES_TO_INSTALL# }"
	fi
	PHP_MODULES_TO_INSTALL="$PHP_MODULES_TO_INSTALL $1"
}

# Sort the modules to be installed, in order to fix dependencies
#
# Update:
#   PHP_MODULES_TO_INSTALL
#
# Output:
#   Nothing
sortModulesToInstall() {
	# apcu_bc requires apcu
	checkRequiredModule 'apcu_bc' 'apcu'
	# http requires propro (for PHP < 8) and raphf
	if test $PHP_MAJMIN_VERSION -le 704; then
		checkRequiredModule 'http' 'propro'
	fi
	checkRequiredModule 'http' 'raphf'
	# Some module installation may use igbinary if available: move it before other modules
	if stringInList 'igbinary' "$PHP_MODULES_TO_INSTALL"; then
		PHP_MODULES_TO_INSTALL="$(removeStringFromList 'igbinary' "$PHP_MODULES_TO_INSTALL")"
		PHP_MODULES_TO_INSTALL="igbinary $PHP_MODULES_TO_INSTALL"
		PHP_MODULES_TO_INSTALL="${PHP_MODULES_TO_INSTALL% }"
	fi
	# Some module installation may use msgpack if available: move it before other modules
	if stringInList 'msgpack' "$PHP_MODULES_TO_INSTALL"; then
		PHP_MODULES_TO_INSTALL="$(removeStringFromList 'msgpack' "$PHP_MODULES_TO_INSTALL")"
		PHP_MODULES_TO_INSTALL="msgpack $PHP_MODULES_TO_INSTALL"
		PHP_MODULES_TO_INSTALL="${PHP_MODULES_TO_INSTALL% }"
	fi
	# Some module installation may use socket if available: move it before other modules
	if stringInList 'socket' "$PHP_MODULES_TO_INSTALL"; then
		PHP_MODULES_TO_INSTALL="$(removeStringFromList 'socket' "$PHP_MODULES_TO_INSTALL")"
		PHP_MODULES_TO_INSTALL="socket $PHP_MODULES_TO_INSTALL"
		PHP_MODULES_TO_INSTALL="${PHP_MODULES_TO_INSTALL% }"
	fi
	# In any case, first of all, we need to install composer
	if stringInList '@composer' "$PHP_MODULES_TO_INSTALL"; then
		PHP_MODULES_TO_INSTALL="$(removeStringFromList '@composer' "$PHP_MODULES_TO_INSTALL")"
		PHP_MODULES_TO_INSTALL="@composer $PHP_MODULES_TO_INSTALL"
		PHP_MODULES_TO_INSTALL="${PHP_MODULES_TO_INSTALL% }"
	fi
}

# Get the required APT/APK packages for a specific PHP version and for the list of module handles
#
# Arguments:
#   $@: the PHP module handles
#
# Set:
#   PACKAGES_PERSISTENT
#   PACKAGES_VOLATILE
#   PACKAGES_PREVIOUS
buildRequiredPackageLists() {
	buildRequiredPackageLists_persistent=''
	buildRequiredPackageLists_volatile=''
	case "$DISTRO" in
		alpine)
			apk update
			;;
	esac
	case "$DISTRO_VERSION" in
		alpine@*)
			if test $# -gt 1 || test "${1:-}" != '@composer'; then
				buildRequiredPackageLists_volatile="$buildRequiredPackageLists_volatile $PHPIZE_DEPS"
			fi
			if test -z "$(apk info 2>/dev/null | grep -E ^libssl)"; then
				buildRequiredPackageLists_libssl='libssl1.0'
			elif test -z "$(apk info 2>/dev/null | grep -E '^libressl.*-libtls')"; then
				buildRequiredPackageLists_libssl=$(apk search -q libressl*-libtls)
			else
				buildRequiredPackageLists_libssl=''
			fi
			;;
		debian@9)
			buildRequiredPackageLists_libssldev='libssl1.0-dev'
			;;
		debian@*)
			buildRequiredPackageLists_libssldev='libssl([0-9]+(\.[0-9]+)*)?-dev$'
			;;
	esac
	if test $USE_PICKLE -gt 1; then
		buildRequiredPackageLists_volatile="$buildRequiredPackageLists_volatile git"
	fi
	while :; do
		if test $# -lt 1; then
			break
		fi
		case "$1@$DISTRO" in
			amqp@alpine)
				buildRequiredPackageLists_persistent="$buildRequiredPackageLists_persistent rabbitmq-c"
				buildRequiredPackageLists_volatile="$buildRequiredPackageLists_volatile rabbitmq-c-dev"
				;;
			amqp@debian)
				buildRequiredPackageLists_persistent="$buildRequiredPackageLists_persistent librabbitmq[0-9]"
				buildRequiredPackageLists_volatile="$buildRequiredPackageLists_volatile librabbitmq-dev libssh-dev"
				;;
			bz2@alpine)
				buildRequiredPackageLists_persistent="$buildRequiredPackageLists_persistent libbz2"
				buildRequiredPackageLists_volatile="$buildRequiredPackageLists_volatile bzip2-dev"
				;;
			bz2@debian)
				buildRequiredPackageLists_volatile="$buildRequiredPackageLists_volatile libbz2-dev"
				;;
			cmark@alpine)
				buildRequiredPackageLists_volatile="$buildRequiredPackageLists_volatile cmake"
				;;
			cmark@debian)
				buildRequiredPackageLists_volatile="$buildRequiredPackageLists_volatile cmake"
				;;
			dba@alpine)
				buildRequiredPackageLists_persistent="$buildRequiredPackageLists_persistent db"
				buildRequiredPackageLists_volatile="$buildRequiredPackageLists_volatile db-dev"
				;;
			dba@debian)
				buildRequiredPackageLists_volatile="$buildRequiredPackageLists_volatile libdb5.3-dev"
				if test $PHP_MAJMIN_VERSION -le 505; then
					buildRequiredPackageLists_volatile="$buildRequiredPackageLists_volatile patch"
				fi
				;;
			decimal@debian)
				buildRequiredPackageLists_persistent="$buildRequiredPackageLists_persistent libmpdec2"
				buildRequiredPackageLists_volatile="$buildRequiredPackageLists_volatile libmpdec-dev"
				;;
			enchant@alpine)
				if test $DISTRO_MAJMIN_VERSION -ge 312; then
					buildRequiredPackageLists_persistent="$buildRequiredPackageLists_persistent enchant2"
					buildRequiredPackageLists_volatile="$buildRequiredPackageLists_volatile enchant2-dev"
				else
					buildRequiredPackageLists_persistent="$buildRequiredPackageLists_persistent enchant"
					buildRequiredPackageLists_volatile="$buildRequiredPackageLists_volatile enchant-dev"
				fi
				;;
			enchant@debian)
				buildRequiredPackageLists_persistent="$buildRequiredPackageLists_persistent libenchant1c2a"
				buildRequiredPackageLists_volatile="$buildRequiredPackageLists_volatile libenchant-dev"
				;;
			ffi@alpine)
				buildRequiredPackageLists_persistent="$buildRequiredPackageLists_persistent libffi"
				buildRequiredPackageLists_volatile="$buildRequiredPackageLists_volatile libffi-dev"
				;;
			ffi@debian)
				buildRequiredPackageLists_volatile="$buildRequiredPackageLists_volatile libffi-dev"
				;;
			gd@alpine)
				buildRequiredPackageLists_persistent="$buildRequiredPackageLists_persistent freetype libjpeg-turbo libpng libxpm"
				buildRequiredPackageLists_volatile="$buildRequiredPackageLists_volatile freetype-dev libjpeg-turbo-dev libpng-dev libxpm-dev"
				if test $PHP_MAJMIN_VERSION -le 506; then
					buildRequiredPackageLists_persistent="$buildRequiredPackageLists_persistent libvpx"
					buildRequiredPackageLists_volatile="$buildRequiredPackageLists_volatile libvpx-dev"
				else
					buildRequiredPackageLists_persistent="$buildRequiredPackageLists_persistent libwebp"
					buildRequiredPackageLists_volatile="$buildRequiredPackageLists_volatile libwebp-dev"
				fi
				;;
			gd@debian)
				buildRequiredPackageLists_persistent="$buildRequiredPackageLists_persistent libfreetype6 libjpeg62-turbo libpng[0-9]+-[0-9]+$ libxpm4"
				buildRequiredPackageLists_volatile="$buildRequiredPackageLists_volatile libfreetype6-dev libjpeg62-turbo-dev libpng-dev libxpm-dev"
				if test $PHP_MAJMIN_VERSION -le 506; then
					buildRequiredPackageLists_persistent="$buildRequiredPackageLists_persistent libvpx[0-9]+$"
					buildRequiredPackageLists_volatile="$buildRequiredPackageLists_volatile libvpx-dev"
				else
					buildRequiredPackageLists_persistent="$buildRequiredPackageLists_persistent libwebp[0-9]+$"
					buildRequiredPackageLists_volatile="$buildRequiredPackageLists_volatile libwebp-dev"
				fi
				;;
			gearman@alpine)
				buildRequiredPackageLists_persistent="$buildRequiredPackageLists_persistent libstdc++ libuuid"
				buildRequiredPackageLists_volatile="$buildRequiredPackageLists_volatile boost-dev gperf libmemcached-dev libevent-dev util-linux-dev"
				;;
			gearman@debian)
				buildRequiredPackageLists_persistent="$buildRequiredPackageLists_persistent libgearman[0-9]*$"
				buildRequiredPackageLists_volatile="$buildRequiredPackageLists_volatile libgearman-dev"
				;;
			geoip@alpine)
				buildRequiredPackageLists_persistent="$buildRequiredPackageLists_persistent geoip"
				buildRequiredPackageLists_volatile="$buildRequiredPackageLists_volatile geoip-dev"
				;;
			geoip@debian)
				buildRequiredPackageLists_persistent="$buildRequiredPackageLists_persistent libgeoip1[0-9]*$"
				buildRequiredPackageLists_volatile="$buildRequiredPackageLists_volatile libgeoip-dev"
				;;
			gettext@alpine)
				buildRequiredPackageLists_persistent="$buildRequiredPackageLists_persistent libintl"
				buildRequiredPackageLists_volatile="$buildRequiredPackageLists_volatile gettext-dev"
				;;
			gmagick@alpine)
				buildRequiredPackageLists_persistent="$buildRequiredPackageLists_persistent graphicsmagick libgomp"
				buildRequiredPackageLists_volatile="$buildRequiredPackageLists_volatile graphicsmagick-dev libtool"
				;;
			gmagick@debian)
				buildRequiredPackageLists_persistent="$buildRequiredPackageLists_persistent libgraphicsmagick(-q16-)?[0-9]*$"
				buildRequiredPackageLists_volatile="$buildRequiredPackageLists_volatile libgraphicsmagick1-dev"
				;;
			gmp@alpine)
				buildRequiredPackageLists_persistent="$buildRequiredPackageLists_persistent gmp"
				buildRequiredPackageLists_volatile="$buildRequiredPackageLists_volatile gmp-dev"
				;;
			gmp@debian)
				buildRequiredPackageLists_volatile="$buildRequiredPackageLists_volatile libgmp-dev"
				;;
			gnupg@alpine)
				buildRequiredPackageLists_persistent="$buildRequiredPackageLists_persistent gpgme"
				buildRequiredPackageLists_volatile="$buildRequiredPackageLists_volatile gpgme-dev"
				;;
			gnupg@debian)
				buildRequiredPackageLists_persistent="$buildRequiredPackageLists_persistent libgpgme[0-9]*$"
				buildRequiredPackageLists_volatile="$buildRequiredPackageLists_volatile libgpgme[0-9]*-dev"
				;;
			grpc@alpine)
				buildRequiredPackageLists_persistent="$buildRequiredPackageLists_persistent libstdc++"
				buildRequiredPackageLists_volatile="$buildRequiredPackageLists_volatile zlib-dev linux-headers"
				;;
			grpc@debian)
				buildRequiredPackageLists_volatile="$buildRequiredPackageLists_volatile zlib1g-dev"
				;;
			http@alpine)
				buildRequiredPackageLists_persistent="$buildRequiredPackageLists_persistent libevent"
				buildRequiredPackageLists_volatile="$buildRequiredPackageLists_volatile zlib-dev curl-dev libevent-dev"
				if test $PHP_MAJMIN_VERSION -le 506; then
					buildRequiredPackageLists_persistent="$buildRequiredPackageLists_persistent libidn"
					buildRequiredPackageLists_volatile="$buildRequiredPackageLists_volatile libidn-dev"
				else
					buildRequiredPackageLists_persistent="$buildRequiredPackageLists_persistent icu-libs libidn"
					buildRequiredPackageLists_volatile="$buildRequiredPackageLists_volatile icu-dev libidn-dev"
				fi
				;;
			http@debian)
				buildRequiredPackageLists_persistent="$buildRequiredPackageLists_persistent libcurl3-gnutls libevent[0-9\.\-]*$"
				buildRequiredPackageLists_volatile="$buildRequiredPackageLists_volatile zlib1g-dev libgnutls28-dev libcurl4-gnutls-dev libevent-dev"
				if test $PHP_MAJMIN_VERSION -le 506; then
					buildRequiredPackageLists_volatile="$buildRequiredPackageLists_volatile libidn1[0-9+]-dev$"
				else
					buildRequiredPackageLists_persistent="$buildRequiredPackageLists_persistent libicu[0-9]+$ libidn2-[0-9+]$"
					buildRequiredPackageLists_volatile="$buildRequiredPackageLists_volatile libicu-dev libidn2-[0-9+]-dev$"
				fi
				;;
			imagick@alpine)
				buildRequiredPackageLists_persistent="$buildRequiredPackageLists_persistent imagemagick"
				buildRequiredPackageLists_volatile="$buildRequiredPackageLists_volatile imagemagick-dev"
				;;
			imagick@debian)
				buildRequiredPackageLists_persistent="$buildRequiredPackageLists_persistent libmagickwand-6.q16-[0-9]+ libmagickcore-6.q16-[0-9]+-extra$"
				buildRequiredPackageLists_volatile="$buildRequiredPackageLists_volatile libmagickwand-dev"
				;;
			imap@alpine)
				buildRequiredPackageLists_persistent="$buildRequiredPackageLists_persistent c-client $buildRequiredPackageLists_libssl"
				buildRequiredPackageLists_volatile="$buildRequiredPackageLists_volatile krb5-dev imap-dev libressl-dev"
				;;
			imap@debian)
				buildRequiredPackageLists_persistent="$buildRequiredPackageLists_persistent libc-client2007e"
				buildRequiredPackageLists_volatile="$buildRequiredPackageLists_volatile libkrb5-dev"
				case "$DISTRO_VERSION" in
					debian@9)
						buildRequiredPackageLists_volatile="$buildRequiredPackageLists_volatile $buildRequiredPackageLists_libssldev comerr-dev krb5-multidev libc-client2007e libgssrpc4 libkadm5clnt-mit11 libkadm5srv-mit11 libkdb5-8 libpam0g-dev libssl-doc mlock"
						;;
					*)
						buildRequiredPackageLists_volatile="$buildRequiredPackageLists_volatile libc-client-dev"
						;;
				esac
				;;
			interbase@alpine)
				buildRequiredPackageLists_volatile="$buildRequiredPackageLists_volatile icu-dev ncurses-dev"
				;;
			interbase@debian)
				buildRequiredPackageLists_persistent="$buildRequiredPackageLists_persistent libfbclient2"
				buildRequiredPackageLists_volatile="$buildRequiredPackageLists_volatile firebird-dev libib-util"
				;;
			intl@alpine)
				buildRequiredPackageLists_persistent="$buildRequiredPackageLists_persistent icu-libs"
				buildRequiredPackageLists_volatile="$buildRequiredPackageLists_volatile icu-dev"
				;;
			intl@debian)
				buildRequiredPackageLists_persistent="$buildRequiredPackageLists_persistent libicu[0-9]+$"
				buildRequiredPackageLists_volatile="$buildRequiredPackageLists_volatile libicu-dev"
				;;
			ldap@alpine)
				buildRequiredPackageLists_persistent="$buildRequiredPackageLists_persistent libldap"
				buildRequiredPackageLists_volatile="$buildRequiredPackageLists_volatile openldap-dev"
				;;
			ldap@debian)
				buildRequiredPackageLists_volatile="$buildRequiredPackageLists_volatile libldap2-dev"
				;;
			maxminddb@alpine)
				buildRequiredPackageLists_persistent="$buildRequiredPackageLists_persistent libmaxminddb"
				buildRequiredPackageLists_volatile="$buildRequiredPackageLists_volatile libmaxminddb-dev"
				;;
			maxminddb@debian)
				buildRequiredPackageLists_persistent="$buildRequiredPackageLists_persistent libmaxminddb[0-9]*$"
				buildRequiredPackageLists_volatile="$buildRequiredPackageLists_volatile libmaxminddb-dev"
				;;
			mcrypt@alpine)
				buildRequiredPackageLists_persistent="$buildRequiredPackageLists_persistent libmcrypt"
				buildRequiredPackageLists_volatile="$buildRequiredPackageLists_volatile libmcrypt-dev"
				;;
			mcrypt@debian)
				buildRequiredPackageLists_persistent="$buildRequiredPackageLists_persistent libmcrypt4"
				buildRequiredPackageLists_volatile="$buildRequiredPackageLists_volatile libmcrypt-dev"
				;;
			memcache@alpine)
				buildRequiredPackageLists_volatile="$buildRequiredPackageLists_volatile zlib-dev"
				;;
			memcache@debian)
				buildRequiredPackageLists_volatile="$buildRequiredPackageLists_volatile zlib1g-dev"
				;;
			memcached@alpine)
				buildRequiredPackageLists_persistent="$buildRequiredPackageLists_persistent libmemcached-libs"
				buildRequiredPackageLists_volatile="$buildRequiredPackageLists_volatile libmemcached-dev zlib-dev"
				;;
			memcached@debian)
				buildRequiredPackageLists_persistent="$buildRequiredPackageLists_persistent libmemcachedutil2"
				buildRequiredPackageLists_volatile="$buildRequiredPackageLists_volatile libmemcached-dev zlib1g-dev"
				;;
			mongo@alpine)
				buildRequiredPackageLists_persistent="$buildRequiredPackageLists_persistent libsasl $buildRequiredPackageLists_libssl"
				buildRequiredPackageLists_volatile="$buildRequiredPackageLists_volatile libressl-dev cyrus-sasl-dev"
				;;
			mongo@debian)
				buildRequiredPackageLists_volatile="$buildRequiredPackageLists_volatile $buildRequiredPackageLists_libssldev libsasl2-dev"
				;;
			mongodb@alpine)
				buildRequiredPackageLists_persistent="$buildRequiredPackageLists_persistent icu-libs libsasl $buildRequiredPackageLists_libssl snappy"
				buildRequiredPackageLists_volatile="$buildRequiredPackageLists_volatile icu-dev cyrus-sasl-dev snappy-dev libressl-dev zlib-dev"
				;;
			mongodb@debian)
				buildRequiredPackageLists_persistent="$buildRequiredPackageLists_persistent libsnappy[0-9]+(v[0-9]+)?$ libicu[0-9]+$"
				buildRequiredPackageLists_volatile="$buildRequiredPackageLists_volatile libicu-dev libsasl2-dev libsnappy-dev $buildRequiredPackageLists_libssldev zlib1g-dev"
				;;
			mosquitto@alpine)
				buildRequiredPackageLists_persistent="$buildRequiredPackageLists_persistent mosquitto-libs"
				buildRequiredPackageLists_volatile="$buildRequiredPackageLists_volatile mosquitto-dev"
				;;
			mosquitto@debian)
				buildRequiredPackageLists_persistent="$buildRequiredPackageLists_persistent libmosquitto1"
				buildRequiredPackageLists_volatile="$buildRequiredPackageLists_volatile libmosquitto-dev"
				;;
			mssql@alpine)
				buildRequiredPackageLists_persistent="$buildRequiredPackageLists_persistent freetds"
				buildRequiredPackageLists_volatile="$buildRequiredPackageLists_volatile freetds-dev"
				;;
			mssql@debian)
				buildRequiredPackageLists_persistent="$buildRequiredPackageLists_persistent libsybdb5"
				buildRequiredPackageLists_volatile="$buildRequiredPackageLists_volatile freetds-dev"
				;;
			oauth@alpine)
				if test $PHP_MAJMIN_VERSION -ge 700; then
					buildRequiredPackageLists_volatile="$buildRequiredPackageLists_volatile pcre-dev"
				fi
				;;
			oauth@debian)
				if test $PHP_MAJMIN_VERSION -ge 700; then
					buildRequiredPackageLists_volatile="$buildRequiredPackageLists_volatile libpcre3-dev"
				fi
				;;
			oci8@alpine | pdo_oci@alpine)
				buildRequiredPackageLists_persistent="$buildRequiredPackageLists_persistent libaio libc6-compat libnsl"
				if test $DISTRO_MAJMIN_VERSION -le 307; then
					# The unzip tool of Alpine 3.7 can't extract symlinks from ZIP archives: let's use bsdtar instead
					buildRequiredPackageLists_volatile="$buildRequiredPackageLists_volatile libarchive-tools"
				fi
				;;
			oci8@debian | pdo_oci@debian)
				buildRequiredPackageLists_persistent="$buildRequiredPackageLists_persistent libaio[0-9]*$"
				buildRequiredPackageLists_volatile="$buildRequiredPackageLists_volatile unzip"
				;;
			odbc@alpine | pdo_odbc@alpine)
				buildRequiredPackageLists_persistent="$buildRequiredPackageLists_persistent unixodbc"
				buildRequiredPackageLists_volatile="$buildRequiredPackageLists_volatile unixodbc-dev"
				;;
			odbc@debian | pdo_odbc@debian)
				buildRequiredPackageLists_persistent="$buildRequiredPackageLists_persistent libodbc1"
				buildRequiredPackageLists_volatile="$buildRequiredPackageLists_volatile unixodbc-dev"
				;;
			pdo_dblib@alpine)
				buildRequiredPackageLists_persistent="$buildRequiredPackageLists_persistent freetds"
				buildRequiredPackageLists_volatile="$buildRequiredPackageLists_volatile freetds-dev"
				;;
			pdo_dblib@debian)
				buildRequiredPackageLists_persistent="$buildRequiredPackageLists_persistent libsybdb5"
				buildRequiredPackageLists_volatile="$buildRequiredPackageLists_volatile freetds-dev"
				;;
			pdo_firebird@alpine)
				buildRequiredPackageLists_volatile="$buildRequiredPackageLists_volatile icu-dev ncurses-dev"
				;;
			pdo_firebird@debian)
				buildRequiredPackageLists_persistent="$buildRequiredPackageLists_persistent libfbclient2"
				buildRequiredPackageLists_volatile="$buildRequiredPackageLists_volatile firebird-dev libib-util"
				;;
			pgsql@alpine | pdo_pgsql@alpine)
				buildRequiredPackageLists_persistent="$buildRequiredPackageLists_persistent postgresql-libs"
				buildRequiredPackageLists_volatile="$buildRequiredPackageLists_volatile postgresql-dev"
				;;
			pgsql@debian | pdo_pgsql@debian)
				buildRequiredPackageLists_persistent="$buildRequiredPackageLists_persistent libpq5"
				buildRequiredPackageLists_volatile="$buildRequiredPackageLists_volatile libpq-dev"
				;;
			pspell@alpine)
				buildRequiredPackageLists_persistent="$buildRequiredPackageLists_persistent aspell-libs"
				buildRequiredPackageLists_volatile="$buildRequiredPackageLists_volatile aspell-dev"
				;;
			pspell@debian)
				buildRequiredPackageLists_persistent="$buildRequiredPackageLists_persistent libaspell15"
				buildRequiredPackageLists_volatile="$buildRequiredPackageLists_volatile libpspell-dev"
				;;
			rdkafka@alpine)
				buildRequiredPackageLists_persistent="$buildRequiredPackageLists_persistent librdkafka"
				buildRequiredPackageLists_volatile="$buildRequiredPackageLists_volatile librdkafka-dev"
				;;
			rdkafka@debian)
				buildRequiredPackageLists_persistent="$buildRequiredPackageLists_persistent librdkafka\+*[0-9]*$"
				buildRequiredPackageLists_volatile="$buildRequiredPackageLists_volatile librdkafka-dev"
				;;
			recode@alpine)
				buildRequiredPackageLists_persistent="$buildRequiredPackageLists_persistent recode"
				buildRequiredPackageLists_volatile="$buildRequiredPackageLists_volatile recode-dev"
				;;
			recode@debian)
				buildRequiredPackageLists_persistent="$buildRequiredPackageLists_persistent librecode0"
				buildRequiredPackageLists_volatile="$buildRequiredPackageLists_volatile librecode-dev"
				;;
			redis@alpine)
				if test $PHP_MAJMIN_VERSION -ge 700; then
					case "$DISTRO_VERSION" in
						alpine@3.7)
							buildRequiredPackageLists_persistent="$buildRequiredPackageLists_persistent zstd"
							;;
						*)
							buildRequiredPackageLists_persistent="$buildRequiredPackageLists_persistent zstd-libs"
							;;
					esac
					buildRequiredPackageLists_volatile="$buildRequiredPackageLists_volatile zstd-dev"
				fi
				;;
			redis@debian)
				if test $PHP_MAJMIN_VERSION -ge 700; then
					case "$DISTRO_VERSION" in
						debian@8)
							## There's no APT package for libzstd
							;;
						debian@9)
							## libzstd is too old (available: 1.1.2, required: 1.3.0+)
							;;
						*)
							buildRequiredPackageLists_persistent="$buildRequiredPackageLists_persistent libzstd[0-9]*$"
							buildRequiredPackageLists_volatile="$buildRequiredPackageLists_volatile libzstd-dev"
							;;
					esac
				fi
				;;
			smbclient@alpine)
				buildRequiredPackageLists_persistent="$buildRequiredPackageLists_persistent libsmbclient"
				buildRequiredPackageLists_volatile="$buildRequiredPackageLists_volatile samba-dev"
				;;
			smbclient@debian)
				buildRequiredPackageLists_persistent="$buildRequiredPackageLists_persistent libsmbclient"
				buildRequiredPackageLists_volatile="$buildRequiredPackageLists_volatile libsmbclient-dev"
				;;
			snmp@alpine)
				buildRequiredPackageLists_persistent="$buildRequiredPackageLists_persistent net-snmp-libs"
				buildRequiredPackageLists_volatile="$buildRequiredPackageLists_volatile net-snmp-dev"
				;;
			snmp@debian)
				buildRequiredPackageLists_persistent="$buildRequiredPackageLists_persistent snmp"
				buildRequiredPackageLists_volatile="$buildRequiredPackageLists_volatile libsnmp-dev"
				;;
			snuffleupagus@alpine)
				buildRequiredPackageLists_persistent="$buildRequiredPackageLists_persistent pcre"
				buildRequiredPackageLists_volatile="$buildRequiredPackageLists_volatile pcre-dev"
				;;
			snuffleupagus@debian)
				buildRequiredPackageLists_volatile="$buildRequiredPackageLists_volatile libpcre3-dev"
				;;
			soap@alpine)
				buildRequiredPackageLists_volatile="$buildRequiredPackageLists_volatile libxml2-dev"
				;;
			soap@debian)
				buildRequiredPackageLists_volatile="$buildRequiredPackageLists_volatile libxml2-dev"
				;;
			solr@alpine)
				buildRequiredPackageLists_volatile="$buildRequiredPackageLists_volatile curl-dev libxml2-dev"
				;;
			solr@debian)
				buildRequiredPackageLists_persistent="$buildRequiredPackageLists_persistent libcurl3-gnutls"
				buildRequiredPackageLists_volatile="$buildRequiredPackageLists_volatile libcurl4-gnutls-dev libxml2-dev"
				;;
			sqlsrv@alpine | pdo_sqlsrv@alpine)
				buildRequiredPackageLists_persistent="$buildRequiredPackageLists_persistent libstdc++ unixodbc"
				buildRequiredPackageLists_volatile="$buildRequiredPackageLists_volatile unixodbc-dev"
				;;
			sqlsrv@debian | pdo_sqlsrv@debian)
				buildRequiredPackageLists_persistent="$buildRequiredPackageLists_persistent unixodbc"
				buildRequiredPackageLists_volatile="$buildRequiredPackageLists_volatile unixodbc-dev"
				if ! isMicrosoftSqlServerODBCInstalled; then
					buildRequiredPackageLists_volatile="$buildRequiredPackageLists_volatile gnupg apt-transport-https"
				fi
				;;
			ssh2@alpine)
				buildRequiredPackageLists_persistent="$buildRequiredPackageLists_persistent libssh2"
				buildRequiredPackageLists_volatile="$buildRequiredPackageLists_volatile libssh2-dev"
				;;
			ssh2@debian)
				buildRequiredPackageLists_volatile="$buildRequiredPackageLists_volatile libssh2-1-dev"
				;;
			swoole@alpine)
				buildRequiredPackageLists_persistent="$buildRequiredPackageLists_persistent postgresql-libs libstdc++ $buildRequiredPackageLists_libssl"
				buildRequiredPackageLists_volatile="$buildRequiredPackageLists_volatile curl-dev postgresql-dev linux-headers libressl-dev"
				;;
			swoole@debian)
				buildRequiredPackageLists_persistent="$buildRequiredPackageLists_persistent libcurl3-gnutls libpq5"
				buildRequiredPackageLists_volatile="$buildRequiredPackageLists_volatile $buildRequiredPackageLists_libssldev libcurl4-gnutls-dev libpq-dev"
				;;
			sybase_ct@alpine)
				buildRequiredPackageLists_persistent="$buildRequiredPackageLists_persistent freetds"
				buildRequiredPackageLists_volatile="$buildRequiredPackageLists_volatile freetds-dev"
				;;
			sybase_ct@debian)
				buildRequiredPackageLists_persistent="$buildRequiredPackageLists_persistent libct4"
				buildRequiredPackageLists_volatile="$buildRequiredPackageLists_volatile freetds-dev"
				;;
			tdlib@alpine)
				buildRequiredPackageLists_persistent="$buildRequiredPackageLists_persistent libstdc++ $buildRequiredPackageLists_libssl"
				buildRequiredPackageLists_volatile="$buildRequiredPackageLists_volatile git cmake gperf zlib-dev libressl-dev linux-headers readline-dev"
				;;
			tdlib@debian)
				buildRequiredPackageLists_volatile="$buildRequiredPackageLists_volatile git cmake gperf zlib1g-dev $buildRequiredPackageLists_libssldev"
				;;
			tensor@alpine)
				buildRequiredPackageLists_persistent="$buildRequiredPackageLists_persistent lapack libexecinfo openblas"
				buildRequiredPackageLists_volatile="$buildRequiredPackageLists_volatile lapack-dev libexecinfo-dev openblas-dev"
				if test $DISTRO_MAJMIN_VERSION -le 310; then
					if ! stringInList --force-overwrite "$IPE_APK_FLAGS"; then
						IPE_APK_FLAGS="$IPE_APK_FLAGS --force-overwrite"
					fi
				fi
				;;
			tensor@debian)
				buildRequiredPackageLists_persistent="$buildRequiredPackageLists_persistent liblapacke libopenblas-base"
				buildRequiredPackageLists_volatile="$buildRequiredPackageLists_volatile liblapack-dev libopenblas-dev liblapacke-dev"
				if test $DISTRO_VERSION_NUMBER -ge 10; then
					buildRequiredPackageLists_persistent="$buildRequiredPackageLists_persistent gfortran-8"
					buildRequiredPackageLists_volatile="$buildRequiredPackageLists_volatile libgfortran-8-dev"
				fi
				;;
			tidy@alpine)
				buildRequiredPackageLists_persistent="$buildRequiredPackageLists_persistent tidyhtml-libs"
				buildRequiredPackageLists_volatile="$buildRequiredPackageLists_volatile tidyhtml-dev"
				;;
			tidy@debian)
				buildRequiredPackageLists_persistent="$buildRequiredPackageLists_persistent libtidy5*"
				buildRequiredPackageLists_volatile="$buildRequiredPackageLists_volatile libtidy-dev"
				;;
			uuid@alpine)
				buildRequiredPackageLists_persistent="$buildRequiredPackageLists_persistent libuuid"
				buildRequiredPackageLists_volatile="$buildRequiredPackageLists_volatile util-linux-dev"
				;;
			uuid@debian)
				buildRequiredPackageLists_volatile="$buildRequiredPackageLists_volatile uuid-dev"
				;;
			vips@alpine)
				buildRequiredPackageLists_persistent="$buildRequiredPackageLists_persistent vips"
				buildRequiredPackageLists_volatile="$buildRequiredPackageLists_volatile vips-dev"
				;;
			vips@debian)
				buildRequiredPackageLists_persistent="$buildRequiredPackageLists_persistent libvips"
				buildRequiredPackageLists_volatile="$buildRequiredPackageLists_volatile libvips-dev"
				;;
			wddx@alpine)
				buildRequiredPackageLists_volatile="$buildRequiredPackageLists_volatile libxml2-dev"
				;;
			wddx@debian)
				buildRequiredPackageLists_volatile="$buildRequiredPackageLists_volatile libxml2-dev"
				;;
			xlswriter@alpine)
				buildRequiredPackageLists_volatile="$buildRequiredPackageLists_volatile zlib-dev"
				;;
			xlswriter@debian)
				buildRequiredPackageLists_volatile="$buildRequiredPackageLists_volatile zlib1g-dev"
				;;
			xmlrpc@alpine)
				buildRequiredPackageLists_volatile="$buildRequiredPackageLists_volatile libxml2-dev"
				;;
			xmlrpc@debian)
				buildRequiredPackageLists_volatile="$buildRequiredPackageLists_volatile libxml2-dev"
				;;
			xsl@alpine)
				buildRequiredPackageLists_persistent="$buildRequiredPackageLists_persistent libxslt"
				buildRequiredPackageLists_volatile="$buildRequiredPackageLists_volatile libxslt-dev libgcrypt-dev"
				;;
			xsl@debian)
				buildRequiredPackageLists_persistent="$buildRequiredPackageLists_persistent libxslt1.1"
				buildRequiredPackageLists_volatile="$buildRequiredPackageLists_volatile libxslt-dev"
				;;
			yaml@alpine)
				buildRequiredPackageLists_persistent="$buildRequiredPackageLists_persistent yaml"
				buildRequiredPackageLists_volatile="$buildRequiredPackageLists_volatile yaml-dev"
				;;
			yaml@debian)
				buildRequiredPackageLists_persistent="$buildRequiredPackageLists_persistent libyaml-0-2"
				buildRequiredPackageLists_volatile="$buildRequiredPackageLists_volatile libyaml-dev"
				;;
			yar@alpine)
				buildRequiredPackageLists_volatile="$buildRequiredPackageLists_volatile curl-dev"
				;;
			yar@debian)
				buildRequiredPackageLists_persistent="$buildRequiredPackageLists_persistent libcurl3-gnutls"
				buildRequiredPackageLists_volatile="$buildRequiredPackageLists_volatile libcurl4-gnutls-dev"
				;;
			zip@alpine)
				buildRequiredPackageLists_persistent="$buildRequiredPackageLists_persistent libzip"
				buildRequiredPackageLists_volatile="$buildRequiredPackageLists_volatile cmake gnutls-dev libzip-dev libressl-dev zlib-dev"
				;;
			zip@debian)
				buildRequiredPackageLists_persistent="$buildRequiredPackageLists_persistent libzip[0-9]$"
				buildRequiredPackageLists_volatile="$buildRequiredPackageLists_volatile cmake gnutls-dev $buildRequiredPackageLists_libssldev libzip-dev libbz2-dev zlib1g-dev"
				case "$DISTRO_VERSION" in
					debian@8)
						# Debian Jessie doesn't seem to provide libmbedtls
						;;
					*)
						buildRequiredPackageLists_persistent="$buildRequiredPackageLists_persistent libmbedtls[0-9]*$"
						buildRequiredPackageLists_volatile="$buildRequiredPackageLists_volatile libmbedtls-dev"
						;;
				esac
				;;
			zookeeper@alpine)
				if ! test -f /usr/local/include/zookeeper/zookeeper.h; then
					buildRequiredPackageLists_volatile="$buildRequiredPackageLists_volatile apache-ant automake libtool openjdk8"
				fi
				;;
			zookeeper@debian)
				buildRequiredPackageLists_persistent="$buildRequiredPackageLists_persistent libzookeeper-mt2"
				buildRequiredPackageLists_volatile="$buildRequiredPackageLists_volatile libzookeeper-mt-dev"
				;;
		esac
		shift
	done
	PACKAGES_PERSISTENT=''
	PACKAGES_VOLATILE=''
	PACKAGES_PREVIOUS=''
	if test -z "$buildRequiredPackageLists_persistent$buildRequiredPackageLists_volatile"; then
		return
	fi
	case "$DISTRO" in
		debian)
			DEBIAN_FRONTEND=noninteractive apt-get update -q
			;;
	esac
	if test -n "$buildRequiredPackageLists_persistent"; then
		PACKAGES_PERSISTENT="$(expandPackagesToBeInstalled $buildRequiredPackageLists_persistent)"
		if test -s "$IPE_ERRFLAG_FILE"; then
			exit 1
		fi
	fi
	if test -n "$buildRequiredPackageLists_volatile"; then
		buildRequiredPackageLists_packages="$(expandPackagesToBeInstalled $buildRequiredPackageLists_volatile)"
		if test -s "$IPE_ERRFLAG_FILE"; then
			exit 1
		fi
		resetIFS
		for buildRequiredPackageLists_package in $buildRequiredPackageLists_packages; do
			if ! stringInList "$buildRequiredPackageLists_package" "$PACKAGES_PERSISTENT"; then
				PACKAGES_VOLATILE="$PACKAGES_VOLATILE $buildRequiredPackageLists_package"
			fi
		done
		PACKAGES_VOLATILE="${PACKAGES_VOLATILE# }"
	fi
	if test -n "$PACKAGES_PERSISTENT$PACKAGES_VOLATILE"; then
		case "$DISTRO" in
			debian)
				PACKAGES_PREVIOUS="$(dpkg --get-selections | grep -E '\sinstall$' | awk '{ print $1 }')"
				;;
		esac
	fi
}

# Get the full list of APT/APK packages that will be installed, given the required packages
#
# Arguments:
#   $1: the list of required APT/APK packages
#
# Output:
#   Space-separated list of every APT/APK packages that will be installed
expandPackagesToBeInstalled() {
	expandPackagesToBeInstalled_result=''
	case "$DISTRO" in
		alpine)
			expandPackagesToBeInstalled_log="$(apk add --simulate $@ 2>&1 || printf '\nERROR: apk failed\n')"
			if test -n "$(printf '%s' "$expandPackagesToBeInstalled_log" | grep -E '^ERROR:')"; then
				printf 'FAILED TO LIST THE WHOLE PACKAGE LIST FOR\n' >&2
				printf '%s ' "$@" >&2
				printf '\n\nCOMMAND OUTPUT:\n%s\n' "$expandPackagesToBeInstalled_log" >&2
				echo 'y' >"$IPE_ERRFLAG_FILE"
				exit 1
			fi
			IFS='
'
			for expandPackagesToBeInstalled_line in $expandPackagesToBeInstalled_log; do
				if test -n "$(printf '%s' "$expandPackagesToBeInstalled_line" | grep -E '^\([0-9]*/[0-9]*) Installing ')"; then
					expandPackagesToBeInstalled_result="$expandPackagesToBeInstalled_result $(printf '%s' "$expandPackagesToBeInstalled_line" | cut -d ' ' -f 3)"
				fi
			done
			resetIFS
			;;
		debian)
			expandPackagesToBeInstalled_log="$(DEBIAN_FRONTEND=noninteractive apt-get install -sy --no-install-recommends $@ 2>&1 || printf '\nE: apt-get failed\n')"
			if test -n "$(printf '%s' "$expandPackagesToBeInstalled_log" | grep -E '^E:')"; then
				printf 'FAILED TO LIST THE WHOLE PACKAGE LIST FOR\n' >&2
				printf '%s ' "$@" >&2
				printf '\n\nCOMMAND OUTPUT:\n%s\n' "$expandPackagesToBeInstalled_log" >&2
				echo 'y' >"$IPE_ERRFLAG_FILE"
				exit 1
			fi
			expandPackagesToBeInstalled_inNewPackages=0
			IFS='
'
			for expandPackagesToBeInstalled_line in $expandPackagesToBeInstalled_log; do
				if test $expandPackagesToBeInstalled_inNewPackages -eq 0; then
					if test "$expandPackagesToBeInstalled_line" = 'The following NEW packages will be installed:'; then
						expandPackagesToBeInstalled_inNewPackages=1
					fi
				elif test "$expandPackagesToBeInstalled_line" = "${expandPackagesToBeInstalled_line# }"; then
					break
				else
					resetIFS
					for expandPackagesToBeInstalled_newPackage in $expandPackagesToBeInstalled_line; do
						expandPackagesToBeInstalled_result="$expandPackagesToBeInstalled_result $expandPackagesToBeInstalled_newPackage"
					done
					IFS='
'
				fi
			done
			resetIFS
			;;
	esac
	printf '%s' "${expandPackagesToBeInstalled_result# }"
}

# Retrieve the number of available cores (alternative to nproc if not available)
# Output:
#   The number of processor cores available
getProcessorCount() {
	if command -v nproc >/dev/null 2>&1; then
		nproc
	else
		getProcessorCount_tmp=$(cat /proc/cpuinfo | grep -E '^processor\s*:\s*\d+$' | wc -l)
		if test $getProcessorCount_tmp -ge 1; then
			echo $getProcessorCount_tmp
		else
			echo 1
		fi
	fi
}

# Set these variables:
# - TARGET_TRIPLET the build target tripled (eg 'x86_64-linux-gnu', 'x86_64-alpine-linux-musl')
setTargetTriplet() {
	TARGET_TRIPLET="$(gcc -print-multiarch 2>/dev/null || true)"
	if test -z "$TARGET_TRIPLET"; then
		TARGET_TRIPLET="$(gcc -dumpmachine)"
	fi
}

# Retrieve the number of processors to be used when compiling an extension
#
# Arguments:
#   $1: the handle of the PHP extension to be compiled
# Output:
#   The number of processors to be used
getCompilationProcessorCount() {
	case "$1" in
		'')
			# The above extensions don't support parallel compilation
			echo 1
			;;
		*)
			# All the other extensions support parallel compilation
			getProcessorCount
			;;
	esac
}

# Install the required APT/APK packages
#
# Arguments:
#   $@: the list of APT/APK packages to be installed
installRequiredPackages() {
	printf '### INSTALLING REQUIRED PACKAGES ###\n'
	printf '# Packages to be kept after installation: %s\n' "$PACKAGES_PERSISTENT"
	printf '# Packages to be used only for installation: %s\n' "$PACKAGES_VOLATILE"

	case "$DISTRO" in
		alpine)
			apk add $IPE_APK_FLAGS $PACKAGES_PERSISTENT $PACKAGES_VOLATILE
			;;
		debian)
			DEBIAN_FRONTEND=noninteractive apt-get install --no-install-recommends -qq -y $PACKAGES_PERSISTENT $PACKAGES_VOLATILE
			;;
	esac
}

# Get the version of an installed APT/APK package
#
# Arguments:
#   $1: the name of the installed package
#
# Output:
#   The numeric part of the package version, with from 1 to 3 numbers
#
# Example:
#   1
#   1.2
#   1.2.3
getInstalledPackageVersion() {
	case "$DISTRO" in
		alpine)
			apk info "$1" | head -n1 | cut -c $((${#1} + 2))- | grep -o -E '^[0-9]+(\.[0-9]+){0,2}'
			;;
		debian)
			dpkg-query --showformat='${Version}' --show "$1" 2>/dev/null | grep -o -E '^[0-9]+(\.[0-9]+){0,2}'
			;;
	esac
}

# Compare two versions
#
# Arguments:
#   $1: the first version
#   $2: the second version
#
# Output
#  -1 if $1 is less than $2
#  0 if $1 is the same as $2
#  1 if $1 is greater than $2
compareVersions() {
	compareVersions_v1="$1.0.0"
	compareVersions_v2="$2.0.0"
	compareVersions_vMin="$(printf '%s\n%s' "$compareVersions_v1" "$compareVersions_v2" | sort -t '.' -n -k1,1 -k2,2 -k3,3 | head -n 1)"
	if test "$compareVersions_vMin" != "$compareVersions_v1"; then
		echo '1'
	elif test "$compareVersions_vMin" = "$compareVersions_v2"; then
		echo '0'
	else
		echo '-1'
	fi
}

# Install Oracle Instant Client & SDK
#
# Set:
#   ORACLE_INSTANTCLIENT_LIBPATH
installOracleInstantClient() {
	if test $(php -r 'echo PHP_INT_SIZE;') -eq 4; then
		installOracleInstantClient_client=client
		installOracleInstantClient_version='19.9'
		installOracleInstantClient_ic=https://download.oracle.com/otn_software/linux/instantclient/199000/instantclient-basic-linux-$installOracleInstantClient_version.0.0.0dbru.zip
		installOracleInstantClient_sdk=https://download.oracle.com/otn_software/linux/instantclient/199000/instantclient-sdk-linux-$installOracleInstantClient_version.0.0.0dbru.zip
	else
		installOracleInstantClient_client=client64
		installOracleInstantClient_version='21.1'
		installOracleInstantClient_ic=https://download.oracle.com/otn_software/linux/instantclient/211000/instantclient-basic-linux.x64-$installOracleInstantClient_version.0.0.0.zip
		installOracleInstantClient_sdk=https://download.oracle.com/otn_software/linux/instantclient/211000/instantclient-sdk-linux.x64-$installOracleInstantClient_version.0.0.0.zip
	fi
	ORACLE_INSTANTCLIENT_LIBPATH=/usr/lib/oracle/$installOracleInstantClient_version/$installOracleInstantClient_client/lib
	if ! test -e "$ORACLE_INSTANTCLIENT_LIBPATH"; then
		printf 'Downloading Oracle Instant Client v%s... ' "$installOracleInstantClient_version"
		installOracleInstantClient_src="$(getPackageSource $installOracleInstantClient_ic)"
		mkdir -p "/usr/lib/oracle/$installOracleInstantClient_version/$installOracleInstantClient_client"
		mv "$installOracleInstantClient_src" "$ORACLE_INSTANTCLIENT_LIBPATH"
		echo 'done.'
	fi
	if ! test -e "$ORACLE_INSTANTCLIENT_LIBPATH/sdk"; then
		printf 'Downloading Oracle Instant SDK v%s... ' "$installOracleInstantClient_version"
		installOracleInstantClient_src="$(getPackageSource $installOracleInstantClient_sdk)"
		ln -sf "$installOracleInstantClient_src/sdk" "$ORACLE_INSTANTCLIENT_LIBPATH/sdk"
		UNNEEDED_PACKAGE_LINKS="$UNNEEDED_PACKAGE_LINKS '$ORACLE_INSTANTCLIENT_LIBPATH/sdk'"
		echo 'done.'
	fi
	case "$DISTRO" in
		alpine)
			if ! test -e /usr/lib/libresolv.so.2 && test -e /lib/libc.so.6; then
				ln -s /lib/libc.so.6 /usr/lib/libresolv.so.2
			fi
			installOracleInstantClient_ldconf=/etc/ld-musl-${TARGET_TRIPLET%-alpine-linux-musl}.path
			if test -e "$installOracleInstantClient_ldconf"; then
				if ! cat "$installOracleInstantClient_ldconf" | grep -q "$ORACLE_INSTANTCLIENT_LIBPATH"; then
					cat "$ORACLE_INSTANTCLIENT_LIBPATH" | awk -v suffix=":$ORACLE_INSTANTCLIENT_LIBPATH" '{print NR==1 ? $0suffix : $0}' >"$ORACLE_INSTANTCLIENT_LIBPATH"
				fi
			else
				if test $(php -r 'echo PHP_INT_SIZE;') -eq 4; then
					echo "/lib:/usr/local/lib:/usr/lib:$ORACLE_INSTANTCLIENT_LIBPATH" >"$installOracleInstantClient_ldconf"
				else
					echo "/lib64:/lib:/usr/local/lib:/usr/lib:$ORACLE_INSTANTCLIENT_LIBPATH" >"$installOracleInstantClient_ldconf"
				fi
			fi
			;;
		debian)
			if ! test -e /etc/ld.so.conf.d/oracle-instantclient.conf; then
				echo "$ORACLE_INSTANTCLIENT_LIBPATH" >/etc/ld.so.conf.d/oracle-instantclient.conf
				ldconfig
			fi
			;;
	esac
}

# Check if the Microsoft SQL Server ODBC Driver is installed
#
# Return:
#   0 (true): if the string is in the list
#   1 (false): if the string is not in the list
isMicrosoftSqlServerODBCInstalled() {
	test -d /opt/microsoft/msodbcsql*/
}

# Install the Microsoft SQL Server ODBC Driver
installMicrosoftSqlServerODBC() {
	printf 'Installing the Microsoft SQL Server ODBC Driver\n'
	case "$DISTRO" in
		alpine)
			# https://docs.microsoft.com/en-us/sql/connect/odbc/linux-mac/installing-the-microsoft-odbc-driver-for-sql-server#alpine17
			rm -rf /tmp/src/msodbcsql.apk
			curl -sSLf -o /tmp/src/msodbcsql.apk https://download.microsoft.com/download/e/4/e/e4e67866-dffd-428c-aac7-8d28ddafb39b/msodbcsql17_17.6.1.1-1_amd64.apk
			printf '\n' | apk add --allow-untrusted /tmp/src/msodbcsql.apk
			rm -rf /tmp/src/msodbcsql.apk
			;;
		debian)
			# https://docs.microsoft.com/en-us/sql/connect/odbc/linux-mac/installing-the-microsoft-odbc-driver-for-sql-server#debian17
			printf -- '- installing the Microsoft APT key\n'
			curl -sSLf https://packages.microsoft.com/keys/microsoft.asc | apt-key add -
			if ! test -f /etc/apt/sources.list.d/mssql-release.list; then
				printf -- '- adding the Microsoft APT source list\n'
				curl -sSLf https://packages.microsoft.com/config/debian/$DISTRO_VERSION_NUMBER/prod.list >/etc/apt/sources.list.d/mssql-release.list
				DEBIAN_FRONTEND=noninteractive apt-get -q update
			fi
			printf -- '- installing the APT package\n'
			DEBIAN_FRONTEND=noninteractive ACCEPT_EULA=Y apt-get -qy --no-install-recommends install '^msodbcsql[0-9]+$'
			;;
	esac
}

# Install Composer
installComposer() {
	installComposer_version="$(getWantedPHPModuleVersion @composer)"
	installComposer_version="${installComposer_version#^}"
	if test -z "$installComposer_version"; then
		installComposer_fullname=composer
		installComposer_flags=''
	else
		installComposer_fullname="$(printf 'composer v%s' "$installComposer_version")"
		if printf '%s' "$installComposer_version" | grep -Eq '^[0-9]+$'; then
			installComposer_flags="--$installComposer_version"
		else
			installComposer_flags="--version=$installComposer_version"
		fi
	fi
	printf '### INSTALLING %s ###\n' "$installComposer_fullname"
	actuallyInstallComposer /usr/local/bin composer "$installComposer_flags"
}

# Actually install composer
#
# Arguments:
#   $1: the directory where composer should be installed (required)
#   $2: the composer filename (optional, default: composer)
#   $3. additional flags for the composer installed (optional)
actuallyInstallComposer() {
	actuallyInstallComposer_installer="$(mktemp -p /tmp/src)"
	curl -sSLf -o "$actuallyInstallComposer_installer" https://getcomposer.org/installer
	actuallyInstallComposer_expectedSignature="$(curl -sSLf https://composer.github.io/installer.sig)"
	actuallyInstallComposer_actualSignature="$(php -n -r "echo hash_file('sha384', '$actuallyInstallComposer_installer');")"
	if test "$actuallyInstallComposer_expectedSignature" != "$actuallyInstallComposer_actualSignature"; then
		printf 'Verification of composer installer failed!\nExpected signature: %s\nActual signature: %s\n' "$actuallyInstallComposer_expectedSignature" "$actuallyInstallComposer_actualSignature" >&2
		exit 1
	fi
	actuallyInstallComposer_flags="--install-dir=$1"
	if test -n "${2:-}"; then
		actuallyInstallComposer_flags="$actuallyInstallComposer_flags --filename=$2"
	else
		actuallyInstallComposer_flags="$actuallyInstallComposer_flags --filename=composer"
	fi
	if test -n "${3:-}"; then
		actuallyInstallComposer_flags="$actuallyInstallComposer_flags $3"
	fi
	php "$actuallyInstallComposer_installer" $actuallyInstallComposer_flags
	rm -- "$actuallyInstallComposer_installer"
}

# Install a bundled PHP module given its handle
#
# Arguments:
#   $1: the handle of the PHP module
#
# Set:
#   UNNEEDED_PACKAGE_LINKS
#
# Output:
#   Nothing
installBundledModule() {
	printf '### INSTALLING BUNDLED MODULE %s ###\n' "$1"
	if test -n "$(getWantedPHPModuleVersion "$1")"; then
		printf '### WARNING the module "%s" is bundled with PHP, you can NOT specify a version for it\n' "$1" >&2
	fi
	case "$1" in
		dba)
			if test -e /usr/lib/$TARGET_TRIPLET/libdb-5.3.so && ! test -e /usr/lib/libdb-5.3.so; then
				ln -s /usr/lib/$TARGET_TRIPLET/libdb-5.3.so /usr/lib/
			fi
			if test $PHP_MAJMIN_VERSION -le 505; then
				docker-php-source extract
				patch /usr/src/php/ext/dba/config.m4 <<EOF
@@ -362,7 +362,7 @@
       break
     fi
   done
-  PHP_DBA_DB_CHECK(4, db-5.1 db-5.0 db-4.8 db-4.7 db-4.6 db-4.5 db-4.4 db-4.3 db-4.2 db-4.1 db-4.0 db-4 db4 db, [(void)db_create((DB**)0, (DB_ENV*)0, 0)])
+  PHP_DBA_DB_CHECK(4, db-5.3 db-5.1 db-5.0 db-4.8 db-4.7 db-4.6 db-4.5 db-4.4 db-4.3 db-4.2 db-4.1 db-4.0 db-4 db4 db, [(void)db_create((DB**)0, (DB_ENV*)0, 0)])
 fi
 PHP_DBA_STD_RESULT(db4,Berkeley DB4)
 
EOF
			fi
			docker-php-ext-configure dba --with-db4
			;;
		gd)
			if test $PHP_MAJMIN_VERSION -le 506; then
				docker-php-ext-configure gd --with-gd --with-jpeg-dir --with-png-dir --with-zlib-dir --with-xpm-dir --with-freetype-dir --enable-gd-native-ttf --with-vpx-dir
			elif test $PHP_MAJMIN_VERSION -le 701; then
				docker-php-ext-configure gd --with-gd --with-jpeg-dir --with-png-dir --with-zlib-dir --with-xpm-dir --with-freetype-dir --enable-gd-native-ttf --with-webp-dir
			elif test $PHP_MAJMIN_VERSION -le 703; then
				docker-php-ext-configure gd --with-gd --with-jpeg-dir --with-png-dir --with-zlib-dir --with-xpm-dir --with-freetype-dir --with-webp-dir
			else
				docker-php-ext-configure gd --enable-gd --with-webp --with-jpeg --with-xpm --with-freetype
			fi
			;;
		gmp)
			if test $PHP_MAJMIN_VERSION -le 506; then
				if ! test -f /usr/include/gmp.h; then
					ln -s /usr/include/$TARGET_TRIPLET/gmp.h /usr/include/gmp.h
					UNNEEDED_PACKAGE_LINKS="$UNNEEDED_PACKAGE_LINKS /usr/include/gmp.h"
				fi
			fi
			;;
		imap)
			case "$DISTRO_VERSION" in
				debian@9)
					installBundledModule_tmp="$(pwd)"
					cd /tmp
					apt-get download libc-client2007e-dev
					dpkg -i --ignore-depends=libssl-dev libc-client2007e-dev*
					rm libc-client2007e-dev*
					cd "$installBundledModule_tmp"
					;;
			esac
			PHP_OPENSSL=yes docker-php-ext-configure imap --with-kerberos --with-imap-ssl
			;;
		interbase | pdo_firebird)
			case "$DISTRO" in
				alpine)
					if ! test -d /tmp/src/firebird; then
						mv "$(getPackageSource https://github.com/FirebirdSQL/firebird/releases/download/R2_5_9/Firebird-2.5.9.27139-0.tar.bz2)" /tmp/src/firebird
						cd /tmp/src/firebird
						# Patch rwlock.h (this has been fixed in later release of firebird 3.x)
						sed -i '194s/.*/#if 0/' src/common/classes/rwlock.h
						./configure --with-system-icu
						# -j option can't be used: make targets must be compiled sequentially
						make -s btyacc_binary gpre_boot libfbstatic libfbclient
						cp gen/firebird/lib/libfbclient.so /usr/lib/
						ln -s /usr/lib/libfbclient.so /usr/lib/libfbclient.so.2
						cd - >/dev/null
					fi
					CFLAGS='-I/tmp/src/firebird/src/jrd -I/tmp/src/firebird/src/include -I/tmp/src/firebird/src/include/gen' docker-php-ext-configure $1
					;;
			esac
			;;
		ldap)
			case "$DISTRO" in
				debian)
					docker-php-ext-configure ldap --with-libdir=lib/$TARGET_TRIPLET
					;;
			esac
			;;
		mssql | pdo_dblib)
			if ! test -f /usr/lib/libsybdb.so; then
				ln -s /usr/lib/$TARGET_TRIPLET/libsybdb.so /usr/lib/libsybdb.so
				UNNEEDED_PACKAGE_LINKS="$UNNEEDED_PACKAGE_LINKS /usr/lib/libsybdb.so"
			fi
			;;
		odbc)
			docker-php-source extract
			cd /usr/src/php/ext/odbc
			phpize
			sed -ri 's@^ *test +"\$PHP_.*" *= *"no" *&& *PHP_.*=yes *$@#&@g' configure
			./configure --with-unixODBC=shared,/usr
			cd - >/dev/null
			;;
		oci8 | pdo_oci)
			installOracleInstantClient
			if test "$1" = oci8; then
				docker-php-ext-configure "$1" "--with-oci8=instantclient,$ORACLE_INSTANTCLIENT_LIBPATH"
			elif test "$1" = pdo_oci; then
				docker-php-ext-configure "$1" "--with-pdo-oci=instantclient,$ORACLE_INSTANTCLIENT_LIBPATH"
			fi
			;;
		pdo_odbc)
			docker-php-ext-configure pdo_odbc --with-pdo-odbc=unixODBC,/usr
			;;
		snmp)
			case "$DISTRO" in
				alpine)
					mkdir -p -m 0755 /var/lib/net-snmp/mib_indexes
					;;
			esac
			;;
		sybase_ct)
			docker-php-ext-configure sybase_ct --with-sybase-ct=/usr
			;;
		tidy)
			case "$DISTRO" in
				alpine)
					if ! test -f /usr/include/buffio.h; then
						ln -s /usr/include/tidybuffio.h /usr/include/buffio.h
						UNNEEDED_PACKAGE_LINKS="$UNNEEDED_PACKAGE_LINKS /usr/include/buffio.h"
					fi
					;;
			esac
			;;
		zip)
			if test $PHP_MAJMIN_VERSION -le 505; then
				docker-php-ext-configure zip
			elif test $PHP_MAJMIN_VERSION -le 703; then
				docker-php-ext-configure zip --with-libzip
			else
				docker-php-ext-configure zip --with-zip
			fi
			;;
	esac
	docker-php-ext-install -j$(getProcessorCount) "$1"
	case "$1" in
		imap)
			case "$DISTRO_VERSION" in
				debian@9)
					dpkg -r libc-client2007e-dev
					;;
			esac
			;;
	esac
}

# Fetch a tar.gz file, extract it and returns the path of the extracted folder.
#
# Arguments:
#   $1: the URL of the file to be downloaded
#
# Output:
#   The path of the extracted directory
getPackageSource() {
	mkdir -p /tmp/src
	getPackageSource_tempFile=$(mktemp -p /tmp/src)
	curl -sSLf -o "$getPackageSource_tempFile" "$1"
	getPackageSource_tempDir=$(mktemp -p /tmp/src -d)
	cd "$getPackageSource_tempDir"
	tar -xzf "$getPackageSource_tempFile" 2>/dev/null || tar -xf "$getPackageSource_tempFile" 2>/dev/null || (
		if command -v bsdtar >/dev/null; then
			bsdtar -xf "$getPackageSource_tempFile"
		else
			unzip -q "$getPackageSource_tempFile"
		fi
	)
	cd - >/dev/null
	unlink "$getPackageSource_tempFile"
	getPackageSource_outDir=''
	for getPackageSource_i in $(ls "$getPackageSource_tempDir"); do
		if test -n "$getPackageSource_outDir" || test -f "$getPackageSource_tempDir/$getPackageSource_i"; then
			getPackageSource_outDir=''
			break
		fi
		getPackageSource_outDir="$getPackageSource_tempDir/$getPackageSource_i"
	done
	if test -n "$getPackageSource_outDir"; then
		printf '%s' "$getPackageSource_outDir"
	else
		printf '%s' "$getPackageSource_tempDir"
	fi
}

# Install a PECL/remote PHP module given its handle
#
# Arguments:
#   $1: the handle of the PHP module
installRemoteModule() {
	installRemoteModule_module="$1"
	printf '### INSTALLING REMOTE MODULE %s ###\n' "$installRemoteModule_module"
	installRemoteModule_version="$(resolveWantedPHPModuleVersion "$installRemoteModule_module")"
	rm -rf "$CONFIGURE_FILE"
	installRemoteModule_manuallyInstalled=0
	installRemoteModule_cppflags=''
	case "$installRemoteModule_module" in
		amqp)
			if test -z "$installRemoteModule_version"; then
				if test $PHP_MAJMIN_VERSION -ge 800; then
					if test -z "$installRemoteModule_version"; then
						installRemoteModule_version=df1241852b359cf12c346beaa68de202257efdf1
					fi
					installRemoteModule_src="$(getPackageSource https://codeload.github.com/php-amqp/php-amqp/tar.gz/$installRemoteModule_version)"
					cd -- "$installRemoteModule_src"
					phpize
					./configure
					make -j$(getProcessorCount)
					make install
					installRemoteModule_manuallyInstalled=1
				elif test "$DISTRO_VERSION" = debian@8; then
					# in Debian Jessie we have librammitmq version 0.5.2
					installRemoteModule_version=1.9.3
				elif test $PHP_MAJMIN_VERSION -le 505; then
					installRemoteModule_version=1.9.4
				fi
			fi
			;;
		apcu)
			if test -z "$installRemoteModule_version"; then
				if test $PHP_MAJMIN_VERSION -le 506; then
					installRemoteModule_version=4.0.11
				fi
			fi
			;;
		cmark)
			if test -z "$installRemoteModule_version"; then
				if test $PHP_MAJMIN_VERSION -le 701; then
					installRemoteModule_version=1.1.0
				fi
			fi
			if ! test -e /usr/local/lib/libcmark.so && ! test -e /usr/lib/libcmark.so && ! test -e /usr/lib64/libcmark.so && ! test -e /lib/libcmark.so; then
				cd "$(getPackageSource https://github.com/commonmark/cmark/archive/0.29.0.tar.gz)"
				make -s -j$(getProcessorCount) cmake_build
				make -s -j$(getProcessorCount) install
				cd - >/dev/null
				ldconfig || true
			fi
			;;
		csv)
			if test -z "$installRemoteModule_version"; then
				if test $PHP_MAJMIN_VERSION -le 704; then
					installRemoteModule_version=0.3.1
				fi
			fi
			;;
		decimal)
			case "$DISTRO" in
				alpine)
					if ! test -f /usr/local/lib/libmpdec.so; then
						installRemoteModule_src="$(getPackageSource https://www.bytereef.org/software/mpdecimal/releases/mpdecimal-2.5.1.tar.gz)"
						cd -- "$installRemoteModule_src"
						./configure --disable-cxx
						make -j$(getProcessorCount)
						make install
						cd - >/dev/null
					fi
					;;
			esac
			;;
		gearman)
			if test -z "$installRemoteModule_version"; then
				if test $PHP_MAJMIN_VERSION -le 506; then
					installRemoteModule_version=1.1.2
				fi
			fi
			case "$DISTRO" in
				alpine)
					if ! test -e /usr/local/include/libgearman/gearman.h || ! test -e /usr/local/lib/libgearman.so; then
						installRemoteModule_src="$(getPackageSource https://github.com/gearman/gearmand/releases/download/1.1.19.1/gearmand-1.1.19.1.tar.gz)"
						cd -- "$installRemoteModule_src"
						./configure
						make -j$(getProcessorCount) install-binPROGRAMS
						make -j$(getProcessorCount) install-nobase_includeHEADERS
						cd - >/dev/null
					fi
					;;
			esac
			;;
		geoip)
			if test -z "$installRemoteModule_version"; then
				installRemoteModule_version=beta
			fi
			;;
		geospatial)
			if test -z "$installRemoteModule_version"; then
				if test $PHP_MAJMIN_VERSION -le 506; then
					installRemoteModule_version=0.2.1
				else
					installRemoteModule_version=beta
				fi
			fi
			;;
		gmagick)
			if test -z "$installRemoteModule_version"; then
				if test $PHP_MAJMIN_VERSION -le 506; then
					installRemoteModule_version=1.1.7RC3
				else
					installRemoteModule_version=beta
				fi
			fi
			;;
		grpc)
			if test -z "$installRemoteModule_version"; then
				if test $PHP_MAJMIN_VERSION -le 506; then
					installRemoteModule_version=1.33.1
				fi
			fi
			if test -z "$installRemoteModule_version" || test "$installRemoteModule_version" = 1.35.0; then
				case "$DISTRO_VERSION" in
					alpine@3.13)
						installRemoteModule_cppflags='-Wno-maybe-uninitialized'
						;;
				esac
			fi
			;;
		http)
			if test -z "$installRemoteModule_version"; then
				if test $PHP_MAJMIN_VERSION -le 506; then
					installRemoteModule_version=2.6.0
				elif test $PHP_MAJMIN_VERSION -le 704; then
					installRemoteModule_version=3.2.4
				fi
			fi
			if test $PHP_MAJMIN_VERSION -ge 700; then
				if ! test -e /usr/local/lib/libidnkit.so; then
					installRemoteModule_src="$(getPackageSource https://jprs.co.jp/idn/idnkit-2.3.tar.bz2)"
					cd -- "$installRemoteModule_src"
					./configure
					make -j$(getProcessorCount) install
					cd - >/dev/null
				fi
			fi
			;;
		igbinary)
			if test -z "$installRemoteModule_version"; then
				if test $PHP_MAJMIN_VERSION -le 506; then
					installRemoteModule_version=2.0.8
				fi
			fi
			;;
		imagick)
			if test $PHP_MAJMIN_VERSION -ge 800; then
				if test -z "$installRemoteModule_version"; then
					installRemoteModule_version=132a11fd26675db9eb9f0e9a3e2887c161875206
				fi
				if test "${installRemoteModule_version%.*}" = "$installRemoteModule_version"; then
					installRemoteModule_displayVersion="$installRemoteModule_version"
				else
					installRemoteModule_displayVersion="git--master-$installRemoteModule_version"
				fi
				installRemoteModule_src="$(getPackageSource https://codeload.github.com/Imagick/imagick/tar.gz/$installRemoteModule_version)"
				cd -- "$installRemoteModule_src"
				sed -Ei "s/^([ \t]*#define[ \t]+PHP_IMAGICK_VERSION[ \t]+\")@PACKAGE_VERSION@(\")/\1git--master-$installRemoteModule_displayVersion\2/" php_imagick.h
				phpize
				./configure
				make -j$(getProcessorCount)
				make install
				installRemoteModule_manuallyInstalled=1
			fi
			;;
		inotify)
			if test -z "$installRemoteModule_version"; then
				if test $PHP_MAJMIN_VERSION -le 506; then
					installRemoteModule_version=0.1.6
				fi
			fi
			;;
		ioncube_loader)
			installRemoteModule_src='https://downloads.ioncube.com/loader_downloads/'
			if test $(php -r 'echo PHP_INT_SIZE;') -eq 4; then
				installRemoteModule_src="${installRemoteModule_src}ioncube_loaders_lin_x86.tar.gz"
			else
				installRemoteModule_src="${installRemoteModule_src}ioncube_loaders_lin_x86-64.tar.gz"
			fi
			printf 'Downloading ionCube Loader... '
			installRemoteModule_src="$(getPackageSource $installRemoteModule_src)"
			echo 'done.'
			installRemoteModule_so=$(php -r "printf('ioncube_loader_lin_%s.%s%s.so', PHP_MAJOR_VERSION, PHP_MINOR_VERSION, ZEND_THREAD_SAFE ? '_ts' : '');")
			cp "$installRemoteModule_src/$installRemoteModule_so" "$(getPHPExtensionsDir)/$installRemoteModule_module.so"
			installRemoteModule_manuallyInstalled=1
			;;
		mailparse)
			if test -z "$installRemoteModule_version"; then
				if test $PHP_MAJMIN_VERSION -le 506; then
					installRemoteModule_version=2.1.6
				fi
			fi
			;;
		memcache)
			if test -z "$installRemoteModule_version"; then
				if test $PHP_MAJMIN_VERSION -le 506; then
					installRemoteModule_version=2.2.7
				elif test $PHP_MAJMIN_VERSION -le 704; then
					installRemoteModule_version=4.0.5.2
				fi
			fi
			;;
		memcached)
			if test -z "$installRemoteModule_version"; then
				if test $PHP_MAJMIN_VERSION -le 506; then
					installRemoteModule_version=2.2.0
				fi
			fi
			# Set the path to libmemcached install prefix
			addConfigureOption 'with-libmemcached-dir' 'no'
			if test -z "$installRemoteModule_version" || test $(compareVersions "$installRemoteModule_version" '3.0.0') -ge 0; then
				# Set the path to ZLIB install prefix
				addConfigureOption 'with-zlib-dir' 'no'
				# Use system FastLZ library
				addConfigureOption 'with-system-fastlz' 'no'
				# Enable memcached igbinary serializer support
				if php --ri igbinary >/dev/null 2>/dev/null; then
					addConfigureOption 'enable-memcached-igbinary' 'yes'
				else
					addConfigureOption 'enable-memcached-igbinary' 'no'
				fi
				# Enable memcached msgpack serializer support
				if php --ri msgpack >/dev/null 2>/dev/null; then
					addConfigureOption 'enable-memcached-msgpack' 'yes'
				else
					addConfigureOption 'enable-memcached-msgpack' 'no'
				fi
				# Enable memcached json serializer support
				addConfigureOption 'enable-memcached-json' 'yes'
				# Enable memcached protocol support
				addConfigureOption 'enable-memcached-protocol' 'no' # https://github.com/php-memcached-dev/php-memcached/issues/418#issuecomment-449587972
				# Enable memcached sasl support
				addConfigureOption 'enable-memcached-sasl' 'yes'
				# Enable memcached session handler support
				addConfigureOption 'enable-memcached-session' 'yes'
			fi
			;;
		mongo)
			if test -z "$installRemoteModule_version" || test $(compareVersions "$installRemoteModule_version" '1.5.0') -ge 0; then
				# Build with Cyrus SASL (MongoDB Enterprise Authentication) support?
				addConfigureOption '-with-mongo-sasl' 'yes'
			fi
			;;
		mongodb)
			if test -z "$installRemoteModule_version"; then
				if test $PHP_MAJMIN_VERSION -le 505; then
					installRemoteModule_version=1.5.5
				elif test $PHP_MAJMIN_VERSION -le 506; then
					installRemoteModule_version=1.7.5
				elif test $PHP_MAJMIN_VERSION -le 800; then
					installRemoteModule_version=1.9.0
				fi
			fi
			;;
		mosquitto)
			if test -z "$installRemoteModule_version"; then
				installRemoteModule_version=beta
			fi
			;;
		msgpack)
			if test -z "$installRemoteModule_version"; then
				if test $PHP_MAJMIN_VERSION -le 506; then
					installRemoteModule_version=0.5.7
				fi
			fi
			;;
		oauth)
			if test -z "$installRemoteModule_version"; then
				if test $PHP_MAJMIN_VERSION -le 506; then
					installRemoteModule_version=1.2.3
				fi
			fi
			;;
		opencensus)
			if test -z "$installRemoteModule_version"; then
				installRemoteModule_version=alpha
			fi
			;;
		parallel)
			if test -z "$installRemoteModule_version"; then
				if test $PHP_MAJMIN_VERSION -le 701; then
					installRemoteModule_version=0.8.3
				fi
			fi
			;;
		pcov)
			if test -z "$installRemoteModule_version"; then
				if test $PHP_MAJMIN_VERSION -le 700; then
					installRemoteModule_version=0.9.0
				fi
			fi
			;;
		propro)
			if test -z "$installRemoteModule_version"; then
				if test $PHP_MAJMIN_VERSION -le 506; then
					installRemoteModule_version=1.0.2
				fi
			fi
			;;
		protobuf)
			if test -z "$installRemoteModule_version"; then
				if test $PHP_MAJMIN_VERSION -le 506; then
					installRemoteModule_version=3.12.4
				fi
			fi
			;;
		pthreads)
			if test -z "$installRemoteModule_version"; then
				if test $PHP_MAJMIN_VERSION -le 506; then
					installRemoteModule_version=2.0.10
				fi
			fi
			;;
		raphf)
			if test -z "$installRemoteModule_version"; then
				if test $PHP_MAJMIN_VERSION -le 506; then
					installRemoteModule_version=1.1.2
				fi
			fi
			;;
		rdkafka)
			if test -z "$installRemoteModule_version"; then
				installRemoteModule_version1=''
				if test $PHP_MAJMIN_VERSION -le 505; then
					installRemoteModule_version1=3.0.5
				elif test $PHP_MAJMIN_VERSION -le 506; then
					installRemoteModule_version1=4.1.2
				fi
				installRemoteModule_version2=''
				case "$DISTRO" in
					alpine)
						installRemoteModule_tmp='librdkafka'
						;;
					debian)
						installRemoteModule_tmp='librdkafka*'
						;;
				esac
				if test -n "$installRemoteModule_tmp"; then
					installRemoteModule_tmp="$(getInstalledPackageVersion "$installRemoteModule_tmp")"
					if test -n "$installRemoteModule_tmp" && test $(compareVersions "$installRemoteModule_tmp" '0.11.0') -lt 0; then
						installRemoteModule_version2=3.1.3
					fi
				fi
				if test -z "$installRemoteModule_version1" || test -z "$installRemoteModule_version2"; then
					installRemoteModule_version="$installRemoteModule_version1$installRemoteModule_version2"
				elif test $(compareVersions "$installRemoteModule_version1" "$installRemoteModule_version2") -le 0; then
					installRemoteModule_version="$installRemoteModule_version1"
				else
					installRemoteModule_version="$installRemoteModule_version2"
				fi
			fi
			;;
		redis)
			if test -z "$installRemoteModule_version"; then
				if test $PHP_MAJMIN_VERSION -le 506; then
					installRemoteModule_version=4.3.0
				fi
			fi
			# Enable igbinary serializer support?
			if php --ri igbinary >/dev/null 2>/dev/null; then
				addConfigureOption 'enable-redis-igbinary' 'yes'
			else
				addConfigureOption 'enable-redis-igbinary' 'no'
			fi
			# Enable lzf compression support?
			addConfigureOption 'enable-redis-lzf' 'yes'
			if test -z "$installRemoteModule_version" || test $(compareVersions "$installRemoteModule_version" '5.0.0') -ge 0; then
				if ! test -e /usr/include/zstd.h || ! test -e /usr/lib/libzstd.so -o -e "/usr/lib/$TARGET_TRIPLET/libzstd.so"; then
					installRemoteModule_zstdVersion=1.4.4
					installRemoteModule_zstdVersionMajor=$(echo $installRemoteModule_zstdVersion | cut -d. -f1)
					rm -rf /tmp/src/zstd
					mv "$(getPackageSource https://github.com/facebook/zstd/releases/download/v$installRemoteModule_zstdVersion/zstd-$installRemoteModule_zstdVersion.tar.gz)" /tmp/src/zstd
					cd /tmp/src/zstd
					make V=0 -j$(getProcessorCount) lib
					cp -f lib/libzstd.so "/usr/lib/$TARGET_TRIPLET/libzstd.so.$installRemoteModule_zstdVersion"
					ln -sf "/usr/lib/$TARGET_TRIPLET/libzstd.so.$installRemoteModule_zstdVersion" "/usr/lib/$TARGET_TRIPLET/libzstd.so.$installRemoteModule_zstdVersionMajor"
					ln -sf "/usr/lib/$TARGET_TRIPLET/libzstd.so.$installRemoteModule_zstdVersion" "/usr/lib/$TARGET_TRIPLET/libzstd.so"
					ln -sf /tmp/src/zstd/lib/zstd.h /usr/include/zstd.h
					UNNEEDED_PACKAGE_LINKS="$UNNEEDED_PACKAGE_LINKS /usr/include/zstd.h"
					cd - >/dev/null
				fi
				# Enable zstd compression support?
				addConfigureOption 'enable-redis-zstd' 'yes'
			fi
			;;
		snuffleupagus)
			if test -z "$installRemoteModule_version"; then
				installRemoteModule_version=0.7.0
			fi
			installRemoteModule_src="$(getPackageSource https://codeload.github.com/jvoisin/snuffleupagus/tar.gz/v$installRemoteModule_version)"
			cd "$installRemoteModule_src/src"
			phpize
			./configure --enable-snuffleupagus
			make -j$(getProcessorCount) install
			cd - >/dev/null
			cp -a "$installRemoteModule_src/config/default.rules" "$PHP_INI_DIR/conf.d/snuffleupagus.rules"
			installRemoteModule_manuallyInstalled=1
			;;
		solr)
			if test -z "$installRemoteModule_version"; then
				if test $PHP_MAJMIN_VERSION -le 506; then
					installRemoteModule_version=2.4.0
				fi
			fi
			;;
		sqlsrv | pdo_sqlsrv)
			if test -z "$installRemoteModule_version"; then
				# https://docs.microsoft.com/it-it/sql/connect/php/system-requirements-for-the-php-sql-driver?view=sql-server-2017
				if test $PHP_MAJMIN_VERSION -le 506; then
					installRemoteModule_version=3.0.1
				elif test $PHP_MAJMIN_VERSION -le 700; then
					installRemoteModule_version=5.3.0
				elif test $PHP_MAJMIN_VERSION -le 701; then
					installRemoteModule_version=5.6.1
				elif test $PHP_MAJMIN_VERSION -le 702; then
					installRemoteModule_version=5.8.1
				fi
			fi
			if ! isMicrosoftSqlServerODBCInstalled; then
				installMicrosoftSqlServerODBC
			fi
			;;
		ssh2)
			if test -z "$installRemoteModule_version"; then
				if test $PHP_MAJMIN_VERSION -le 506; then
					installRemoteModule_version=0.13
				else
					installRemoteModule_version=beta
				fi
			fi
			;;
		swoole)
			if test -z "$installRemoteModule_version"; then
				if test $PHP_MAJMIN_VERSION -le 502; then
					installRemoteModule_version=1.6.10
				elif test $PHP_MAJMIN_VERSION -le 504; then
					installRemoteModule_version=2.0.4
				elif test $PHP_MAJMIN_VERSION -le 506; then
					installRemoteModule_version=2.0.11
				elif test $PHP_MAJMIN_VERSION -le 700; then
					installRemoteModule_version=4.3.6
				elif test $PHP_MAJMIN_VERSION -le 701; then
					installRemoteModule_version=4.5.10
				fi
			fi
			if php --ri sockets >/dev/null 2>/dev/null; then
				installRemoteModule_sockets=yes
			else
				installRemoteModule_sockets=no
			fi
			installRemoteModule_openssl=yes
			case "$DISTRO_VERSION" in
				alpine@3.7 | alpine@3.8)
					if test -n "$installRemoteModule_version" && test $(compareVersions "$installRemoteModule_version" 4.6.0) -lt 0; then
						# see https://github.com/swoole/swoole-src/issues/3934
						installRemoteModule_openssl=no
					fi
					;;
			esac
			if test -z "$installRemoteModule_version" || test $(compareVersions "$installRemoteModule_version" 4.6.1) -ge 0; then
				# enable sockets supports?
				addConfigureOption enable-sockets $installRemoteModule_sockets
				# enable openssl support?
				addConfigureOption enable-openssl $installRemoteModule_openssl
				# enable http2 support?
				addConfigureOption enable-http2 yes
				# enable mysqlnd support?
				addConfigureOption enable-mysqlnd yes
				# enable json support?
				addConfigureOption enable-swoole-json yes
				# enable curl support?
				if test $PHP_MAJMINPAT_VERSION -ne 80000; then
					addConfigureOption enable-swoole-curl yes
				else
					# https://github.com/swoole/swoole-src/issues/3977#issuecomment-754755521
					addConfigureOption enable-swoole-curl no
				fi
			elif test $(compareVersions "$installRemoteModule_version" 4.4.0) -ge 0; then
				# enable sockets supports?
				addConfigureOption enable-sockets $installRemoteModule_sockets
				# enable openssl support?
				addConfigureOption enable-openssl $installRemoteModule_openssl
				# enable http2 support?
				addConfigureOption enable-http2 yes
				# enable mysqlnd support?
				addConfigureOption enable-mysqlnd yes
			elif test $(compareVersions "$installRemoteModule_version" 4.2.11) -ge 0; then
				# enable sockets supports?
				addConfigureOption enable-sockets $installRemoteModule_sockets
				# enable openssl support?
				addConfigureOption enable-openssl $installRemoteModule_openssl
				# enable http2 support?
				addConfigureOption enable-http2 yes
				# enable mysqlnd support?
				addConfigureOption enable-mysqlnd yes
				# enable postgresql coroutine client support?
				addConfigureOption enable-coroutine-postgresql yes
			elif test $(compareVersions "$installRemoteModule_version" 4.2.7) -ge 0; then
				# enable sockets supports?
				addConfigureOption enable-sockets $installRemoteModule_sockets
				# enable openssl support?
				addConfigureOption enable-openssl $installRemoteModule_openssl
				# enable http2 support?
				addConfigureOption enable-http2 yes
				# enable mysqlnd support?
				addConfigureOption enable-mysqlnd yes
				# enable postgresql coroutine client support?
				addConfigureOption enable-coroutine-postgresql yes
				# enable kernel debug/trace log? (it will degrade performance)
				addConfigureOption enable-debug-log no
			elif test $(compareVersions "$installRemoteModule_version" 4.2.6) -ge 0; then
				# enable debug/trace log support?
				addConfigureOption enable-debug-log no
				# enable sockets supports?
				addConfigureOption enable-sockets $installRemoteModule_sockets
				# enable openssl support?
				addConfigureOption enable-openssl $installRemoteModule_openssl
				# enable http2 support?
				addConfigureOption enable-http2 yes
				# enable mysqlnd support?
				addConfigureOption enable-mysqlnd yes
				# enable postgresql coroutine client support?
				addConfigureOption enable-coroutine-postgresql yes
			elif test $(compareVersions "$installRemoteModule_version" 4.2.0) -ge 0; then
				# enable debug/trace log support?
				addConfigureOption enable-debug-log no
				# enable sockets supports?
				addConfigureOption enable-sockets $installRemoteModule_sockets
				# enable openssl support?
				addConfigureOption enable-openssl $installRemoteModule_openssl
				# enable http2 support?
				addConfigureOption enable-http2 yes
				# enable async-redis support?
				addConfigureOption enable-async-redis yes
				# enable mysqlnd support?
				addConfigureOption enable-mysqlnd yes
				# enable postgresql coroutine client support?
				addConfigureOption enable-coroutine-postgresql yes
			elif test $(compareVersions "$installRemoteModule_version" 2.1.2) -ge 0; then
				# enable debug/trace log support?
				addConfigureOption enable-swoole-debug no
				# enable sockets supports?
				addConfigureOption enable-sockets $installRemoteModule_sockets
				# enable openssl support?
				addConfigureOption enable-openssl $installRemoteModule_openssl
				# enable http2 support?
				addConfigureOption enable-http2 yes
				# enable async-redis support?
				addConfigureOption enable-async-redis yes
				# enable mysqlnd support?
				addConfigureOption enable-mysqlnd yes
				# enable postgresql coroutine client support?
				addConfigureOption enable-coroutine-postgresql yes
			elif test $(compareVersions "$installRemoteModule_version" 1.10.4) -ge 0 && test $(compareVersions "$installRemoteModule_version" 1.10.5) -le 0; then
				# enable debug/trace log support?
				addConfigureOption enable-swoole-debug no
				# enable sockets supports?
				addConfigureOption enable-sockets $installRemoteModule_sockets
				# enable openssl support?
				addConfigureOption enable-openssl $installRemoteModule_openssl
				# enable http2 support?
				addConfigureOption enable-http2 yes
				# enable async-redis support?
				addConfigureOption enable-async-redis yes
				# enable mysqlnd support?
				addConfigureOption enable-mysqlnd yes
			fi
			;;
		tdlib)
			if ! test -f /usr/lib/libphpcpp.so || ! test -f /usr/include/phpcpp.h; then
				if test $PHP_MAJMIN_VERSION -le 701; then
					cd "$(getPackageSource https://codeload.github.com/CopernicaMarketingSoftware/PHP-CPP/tar.gz/v2.1.4)"
				elif test $PHP_MAJMIN_VERSION -le 703; then
					cd "$(getPackageSource https://codeload.github.com/CopernicaMarketingSoftware/PHP-CPP/tar.gz/v2.2.0)"
				else
					cd "$(getPackageSource https://codeload.github.com/CopernicaMarketingSoftware/PHP-CPP/tar.gz/444d1f90cf6b7f3cb5178fa0d0b5ab441b0389d0)"
				fi
				make -j$(getProcessorCount)
				make install
				cd - >/dev/null
			fi
			installRemoteModule_tmp="$(mktemp -p /tmp/src -d)"
			git clone --depth=1 --recurse-submodules https://github.com/yaroslavche/phptdlib.git "$installRemoteModule_tmp"
			mkdir "$installRemoteModule_tmp/build"
			cd "$installRemoteModule_tmp/build"
			cmake -D USE_SHARED_PHPCPP:BOOL=ON ..
			make
			make install
			rm "$PHP_INI_DIR/conf.d/tdlib.ini"
			installRemoteModule_manuallyInstalled=1
			;;
		tensor)
			if test -z "$installRemoteModule_version"; then
				if test $PHP_MAJMIN_VERSION -le 703; then
					installRemoteModule_version=2.2.3
				fi
			fi
			;;
		uopz)
			if test -z "$installRemoteModule_version"; then
				if test $PHP_MAJMIN_VERSION -le 506; then
					installRemoteModule_version=2.0.7
				elif test $PHP_MAJMIN_VERSION -le 700; then
					installRemoteModule_version=5.0.2
				fi
			fi
			;;
		uuid)
			if test -z "$installRemoteModule_version"; then
				if test $PHP_MAJMIN_VERSION -le 506; then
					installRemoteModule_version=1.0.5
				fi
			fi
			;;
		xdebug)
			if test -z "$installRemoteModule_version"; then
				if test $PHP_MAJMIN_VERSION -le 500; then
					installRemoteModule_version=2.0.5
				elif test $PHP_MAJMIN_VERSION -le 503; then
					installRemoteModule_version=2.2.7
				elif test $PHP_MAJMIN_VERSION -le 504; then
					installRemoteModule_version=2.4.1
				elif test $PHP_MAJMIN_VERSION -le 506; then
					installRemoteModule_version=2.5.5
				elif test $PHP_MAJMIN_VERSION -le 700; then
					installRemoteModule_version=2.6.1
				elif test $PHP_MAJMIN_VERSION -le 701; then
					installRemoteModule_version=2.9.8
				fi
			fi
			;;
		xhprof)
			if test -z "$installRemoteModule_version"; then
				if test $PHP_MAJMIN_VERSION -le 506; then
					installRemoteModule_version=0.9.4
				fi
			fi
			;;
		xlswriter)
			if test -z "$installRemoteModule_version" || test $(compareVersions "$installRemoteModule_version" 1.2.7) -ge 0; then
				# enable reader supports?
				addConfigureOption enable-reader yes
			fi
			;;
		yaml)
			if test -z "$installRemoteModule_version"; then
				if test $PHP_MAJMIN_VERSION -le 506; then
					installRemoteModule_version=1.3.1
				elif test $PHP_MAJMIN_VERSION -le 700; then
					installRemoteModule_version=2.0.4
				fi
			fi
			;;
		yar)
			if test -z "$installRemoteModule_version"; then
				if test $PHP_MAJMIN_VERSION -le 506; then
					installRemoteModule_version=1.2.5
				fi
			fi
			if test -z "$installRemoteModule_version" || test $(compareVersions "$installRemoteModule_version" 1.2.4) -ge 0; then
				# Enable Msgpack Supports
				if php --ri msgpack >/dev/null 2>/dev/null; then
					addConfigureOption enable-msgpack yes
				else
					addConfigureOption enable-msgpack no
				fi
			fi
			;;
		zookeeper)
			case "$DISTRO" in
				alpine)
					if ! test -f /usr/local/include/zookeeper/zookeeper.h; then
						installRemoteModule_tmp="$(curl -sSLf https://downloads.apache.org/zookeeper/stable | sed -E 's/["<>]/\n/g' | grep -E '^(apache-)?zookeeper-[0-9]+\.[0-9]+\.[0-9]+\.(tar\.gz|tgz)$' | head -n1)"
						if test -z "$installRemoteModule_tmp"; then
							echo 'Failed to detect the zookeeper library URL' >&2
							exit 1
						fi
						installRemoteModule_src="$(getPackageSource https://downloads.apache.org/zookeeper/stable/$installRemoteModule_tmp)"
						cd -- "$installRemoteModule_src"
						ant compile_jute
						cd - >/dev/null
						cd -- "$installRemoteModule_src/zookeeper-client/zookeeper-client-c"
						autoreconf -if
						./configure --without-cppunit
						make -j$(getProcessorCount) CFLAGS='-Wno-stringop-truncation -Wno-format-overflow'
						make install
						cd - >/dev/null
					fi
					;;
			esac
			if test -z "$installRemoteModule_version"; then
				if test $PHP_MAJMIN_VERSION -le 506; then
					installRemoteModule_version=0.5.0
				elif test $PHP_MAJMIN_VERSION -ge 703; then
					installRemoteModule_version=beta
				fi
			fi
			;;
	esac
	if test $installRemoteModule_manuallyInstalled -eq 0; then
		if test -n "$installRemoteModule_version"; then
			printf '  (installing version %s)\n' "$installRemoteModule_version"
		fi
		installPeclPackage "$installRemoteModule_module" "$installRemoteModule_version" "$installRemoteModule_cppflags"
	fi
	case "$installRemoteModule_module" in
		apcu_bc)
			# apcu_bc must be loaded after apcu
			docker-php-ext-enable --ini-name "xx-php-ext-$installRemoteModule_module.ini" apc
			;;
		ioncube_loader)
			# On PHP 5.5, docker-php-ext-enable fails to detect that ionCube Loader is a Zend Extension
			if test $PHP_MAJMIN_VERSION -le 505; then
				printf 'zend_extension=%s/%s.so\n' "$(getPHPExtensionsDir)" "$installRemoteModule_module" >"$PHP_INI_DIR/conf.d/docker-php-ext-$installRemoteModule_module.ini"
			else
				docker-php-ext-enable "$installRemoteModule_module"
			fi
			;;
		http | memcached)
			# http must be loaded after raphf and propro, memcached must be loaded after msgpack
			docker-php-ext-enable --ini-name "xx-php-ext-$installRemoteModule_module.ini" "$installRemoteModule_module"
			;;
		snuffleupagus)
			docker-php-ext-enable "$installRemoteModule_module"
			printf 'sp.configuration_file=%s\n' "$PHP_INI_DIR/conf.d/snuffleupagus.rules" >>"$PHP_INI_DIR/conf.d/docker-php-ext-snuffleupagus.ini"
			;;
		*)
			docker-php-ext-enable "$installRemoteModule_module"
			;;
	esac
}

# Configure the PECL package installed
#
# Updates:
#   PHP_MODULES_TO_INSTALL
# Sets:
#   USE_PICKLE
configureInstaller() {
	USE_PICKLE=0
	for PHP_MODULE_TO_INSTALL in $PHP_MODULES_TO_INSTALL; do
		if test "${PHP_MODULE_TO_INSTALL#@}" != "$PHP_MODULE_TO_INSTALL"; then
			continue
		fi
		if test "$PHP_MODULE_TO_INSTALL" = 'amqp' && test $PHP_MAJMIN_VERSION -ge 800; then
			continue
		fi
		if test "$PHP_MODULE_TO_INSTALL" = 'imagick' && test $PHP_MAJMIN_VERSION -ge 800; then
			continue
		fi
		if ! stringInList "$PHP_MODULE_TO_INSTALL" "$BUNDLED_MODULES"; then
			if test $PHP_MAJMIN_VERSION -lt 800; then
				pecl channel-update pecl.php.net || true
				return
			fi
			if false && anyStringInList '' "$PHP_MODULES_TO_INSTALL"; then
				USE_PICKLE=2
			else
				curl -sSLf https://github.com/FriendsOfPHP/pickle/releases/latest/download/pickle.phar -o /tmp/pickle
				chmod +x /tmp/pickle
				USE_PICKLE=1
			fi
			return
		fi
	done
}

buildPickle() {
	printf '### BUILDING PICKLE ###\n'
	buildPickle_tempDir="$(mktemp -p /tmp/src -d)"
	cd -- "$buildPickle_tempDir"
	printf 'Downloading... '
	git clone --quiet --depth 1 https://github.com/FriendsOfPHP/pickle.git .
	git tag 0.7.0
	printf 'done.\n'
	printf 'Installing composer... '
	actuallyInstallComposer . composer '--1 --quiet'
	printf 'done.\n'
	printf 'Installing composer dependencies... '
	./composer install --no-dev --no-progress --no-suggest --optimize-autoloader --ignore-platform-reqs --quiet --no-cache
	printf 'done.\n'
	printf 'Building... '
	php -d phar.readonly=0 box.phar build
	mv pickle.phar /tmp/pickle
	printf 'done.\n'
	cd - >/dev/null
}

# Add a configure option for the pecl/pickle install command
#
# Arguments:
#   $1: the option name
#   $2: the option value
addConfigureOption() {
	if test $USE_PICKLE -eq 0; then
		printf -- '%s\n' "$2" >>"$CONFIGURE_FILE"
	else
		printf -- '--%s=%s\n' "$1" "$2" >>"$CONFIGURE_FILE"
	fi
}

# Actually installs a PECL package
#
# Arguments:
#   $1: the package to be installed
#   $2: the package version to be installed (optional)
#   $3: the value of the CPPFLAGS variable
installPeclPackage() {
	if ! test -f "$CONFIGURE_FILE"; then
		printf '\n' >"$CONFIGURE_FILE"
	fi
	installPeclPackage_name="$(getPeclModuleName "$1")"
	if test -z "${2:-}"; then
		installPeclPackage_fullname="$installPeclPackage_name"
	else
		installPeclPackage_fullname="$installPeclPackage_name-$2"
	fi
	if test $USE_PICKLE -eq 0; then
		cat "$CONFIGURE_FILE" | MAKE="make -j$(getCompilationProcessorCount $1)" CPPFLAGS="${3:-}" pecl install "$installPeclPackage_fullname"
	else
		MAKE="make -j$(getCompilationProcessorCount $1)" CPPFLAGS="${3:-}" /tmp/pickle install --tmp-dir=/tmp/pickle.tmp --no-interaction --version-override='' --with-configure-options "$CONFIGURE_FILE" -- "$installPeclPackage_fullname"
	fi
}

# Check if a string is in a list of space-separated string
#
# Arguments:
#   $1: the string to be checked
#   $2: the string list
#
# Return:
#   0 (true): if the string is in the list
#   1 (false): if the string is not in the list
stringInList() {
	for stringInList_listItem in $2; do
		if test "$1" = "$stringInList_listItem"; then
			return 0
		fi
	done
	return 1
}

# Check if at least one item in a list is in another list
#
# Arguments:
#   $1: the space-separated list of items to be searched
#   $2: the space-separated list of reference items
#
# Return:
#   0 (true): at least one of the items in $1 is in $2
#   1 (false): otherwise
anyStringInList() {
	for anyStringInList_item in $1; do
		if stringInList "$anyStringInList_item" "$2"; then
			return 0
		fi
	done
	return 1
}

# Remove a word from a space-separated list
#
# Arguments:
#   $1: the word to be removed
#   $2: the string list
#
# Output:
#   The list without the word
removeStringFromList() {
	removeStringFromList_result=''
	for removeStringFromList_listItem in $2; do
		if test "$1" != "$removeStringFromList_listItem"; then
			if test -z "$removeStringFromList_result"; then
				removeStringFromList_result="$removeStringFromList_listItem"
			else
				removeStringFromList_result="$removeStringFromList_result $removeStringFromList_listItem"
			fi
		fi
	done
	printf '%s' "$removeStringFromList_result"
}

# Cleanup everything at the end of the execution
cleanup() {
	if test -n "$UNNEEDED_PACKAGE_LINKS"; then
		printf '### REMOVING UNNEEDED PACKAGE LINKS ###\n'
		for cleanup_link in $UNNEEDED_PACKAGE_LINKS; do
			if test -L "$cleanup_link"; then
				rm -f "$cleanup_link"
			fi
		done
	fi
	if test -n "$PACKAGES_VOLATILE"; then
		printf '### REMOVING UNNEEDED PACKAGES ###\n'
		case "$DISTRO" in
			alpine)
				apk del --purge $PACKAGES_VOLATILE
				;;
			debian)
				DEBIAN_FRONTEND=noninteractive apt-get remove --purge -y $PACKAGES_VOLATILE
				;;
		esac
	fi
	if test -n "$PACKAGES_PREVIOUS"; then
		case "$DISTRO" in
			debian)
				printf '### RESTORING PREVIOUSLY INSTALLED PACKAGES ###\n'
				DEBIAN_FRONTEND=noninteractive apt-get install --no-install-recommends --no-upgrade -qqy $PACKAGES_PREVIOUS
				;;
		esac
	fi
	case "$DISTRO" in
		alpine)
			rm -rf /var/cache/apk/*
			;;
		debian)
			rm -rf /var/lib/apt/lists/*
			;;
	esac
	docker-php-source delete
	rm -rf /tmp/pear
	rm -rf /tmp/src
	rm -rf /tmp/pickle
	rm -rf /tmp/pickle.tmp
	rm -rf "$CONFIGURE_FILE"
}

resetIFS
mkdir -p /tmp/src
mkdir -p /tmp/pickle.tmp
IPE_ERRFLAG_FILE="$(mktemp -p /tmp/src)"
CONFIGURE_FILE=/tmp/configure-options
IPE_APK_FLAGS=''
setDistro
case "$DISTRO_VERSION" in
	debian@8)
		fixMaxOpenFiles || true
		;;
esac
setPHPVersionVariables
setPHPPreinstalledModules
case "$PHP_MAJMIN_VERSION" in
	505 | 506 | 700 | 701 | 702 | 703 | 704 | 800) ;;
	*)
		printf "### ERROR: Unsupported PHP version: %s.%s ###\n" $((PHP_MAJMIN_VERSION / 100)) $((PHP_MAJMIN_VERSION % 100))
		;;
esac
UNNEEDED_PACKAGE_LINKS=''
processCommandArguments "$@"

if test -z "$PHP_MODULES_TO_INSTALL"; then
	exit 0
fi

sortModulesToInstall

docker-php-source extract
BUNDLED_MODULES="$(find /usr/src/php/ext -mindepth 2 -maxdepth 2 -type f -name 'config.m4' | xargs -n1 dirname | xargs -n1 basename | xargs)"
configureInstaller

buildRequiredPackageLists $PHP_MODULES_TO_INSTALL
if test -n "$PACKAGES_PERSISTENT$PACKAGES_VOLATILE"; then
	installRequiredPackages
fi
if test "$PHP_MODULES_TO_INSTALL" != '@composer'; then
	setTargetTriplet
fi
if test $USE_PICKLE -gt 1; then
	buildPickle
fi
for PHP_MODULE_TO_INSTALL in $PHP_MODULES_TO_INSTALL; do
	if test "$PHP_MODULE_TO_INSTALL" = '@composer'; then
		installComposer
	elif stringInList "$PHP_MODULE_TO_INSTALL" "$BUNDLED_MODULES"; then
		installBundledModule "$PHP_MODULE_TO_INSTALL"
	else
		installRemoteModule "$PHP_MODULE_TO_INSTALL"
	fi
done
cleanup
