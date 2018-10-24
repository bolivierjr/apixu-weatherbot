#!usr/bin/env tclsh

########################################################################################
# Name              eck0-apixuweather1.0.tcl
#
# Author            eck0
#
# Description       Uses the Apixu weatherAPI to grab the data.
#
#                   Requires channel to be flagged with +weather-apixu
#                       example: .chanset #chan +weather-apixu
#
#                   Commands:
#                       .set 0-2 <location>
#                          - can be 0 for Metric, 1 for Imperial, 2 for both.
#                            i.e. ".set 2 New Orleans, LA"
#                       .wz <location>
#                          - Grabs current weather in location. If no location is given,
#                            will try to use users saved location
#                       .wzf <location>
#                          - Same as .wz but provides a 5 day forecast
#                       
#                       Use the --help or -h flags with any of the commands to
#                       get help with the commands and descriptions.
#
# Version           1.0 - Initial Release
#
# Notes             Grab your own api key at https://apixu.com and place
#                   it in the "apikey" variable below. 
#
########################################################################################

namespace eval weather {
    package require tdom
    package require http
    package require tls

    # To be able to query APIs that use https
    tls::init -tls1 true -ssl2 false -ssl3 false
    http::register https 443 tls::socket

    setudef flag weather-apixu
    # Default units for weather output. 0 for metric, 1 for imperial, 2 for both.
    variable units "1"
    # Set your apikey here
    variable apikey "<insert-your-key-here>"
    # Set to 1 (true by default) if you want all help info and set weather responses
    # to use PM and notify. Set to 0 if you want it all in the channel.
    variable private 0

    bind pub - .wz weather::current_weather
    bind pub - .wzf weather::forecast
    bind pub - .set weather::location

    proc current_weather {nick uhost hand chan text} {
        set text [string trim $text]

        if {$text eq "--help" || $text eq "-h"} {
            _get_help $nick
            return
        }

        if {$text eq ""} {
            # Checks to see if a user has a location set
            set userinfo [_get_userinfo $nick $hand $chan]

            if {$userinfo eq -1} {
                return
            } else {
                puthelp "PRIVMSG $chan :Userinfo is [dict get $userinfo location]"
            }
        }

        
    }

    proc forecast {nick uhost hand chan text} {
        set text [string trim $text]

        if {$text eq "--help" || $text eq "-h"} {
            _get_help $nick
            return
        }
    }

    proc location {nick uhost hand chan text} {
        if {$text eq "--help" || $text eq "-h"} {
            _get_help $nick
            return
        } elseif {$::weather::private} {
            putlog "$::weather::private set to private. Use PM instead."
            puthelp "NOTICE $nick :Please private message me to set your location.\ 
                    i.e. \002'.set 1 <location>'\002 to set your location and use imperial\
                    units."
            return
        }

        set location_info [_set_location $nick $uhost $hand $text]

        if {$location_info eq -1} {
            return
        }

        puthelp "PRIVMSG $chan :Default weather location for \002$nick\002 set to\
                \002[dict get $location_info location]\002 and units set to\
                \002[dict get $location_info units]\002\."
    }

    # Helper functions below
    proc _get_userinfo {nick hand chan} {
        putlog "weather::_getuserinfo looking up user location and units"
        set location [getuser $hand XTRA weather.location]
        set units [getuser $hand XTRA weather.units]
        set userinfo [dict create location $location units $units]

        if {[string length [dict get $userinfo location]] eq 0} {
            putlog "weather::_getusuerinfo did not find info set for $nick"            
            if {$::weather::private} {
                puthelp "NOTICE $nick :Did you want the weather for a specific location?\
                        Or please PM me with the \".set\" command to set a default location."
            } else {
                puthelp "PRIVMSG $chan :No location set or use \002'.wz <location>'\002"
            }
            return -1
        }
 
       return $userinfo 
    }

    proc _get_xml {location type} {
        
    }

    proc _set_location {nick uhost hand text} {
        putlog "weather::location was called"
        putlog "nick: $nick, uhost: $uhost, hand: $hand is trying to set location"
        set text [string trim $text]
        set units [string index $text 0]
        set location [string range $text 2 end]

        if {!($units eq "0" || $units eq "1" || $units eq "2")} {
            putlog "$nick set units to an invalid number."
            puthelp "NOTICE $nick :Units must be specified from 0-2 where 0 = metric,\
                    1 = imperial and 2 = both. i.e. \002'.set 2 New Orleans, LA'\002 would\
                    spam both unit types for New Orleans."
            return -1
        } elseif {![string length $location] > 0} {
            putlog "$nick gave an invalid location"
            puthelp "NOTICE $nick :Must supply a location to be set. i.e. \002'set 1\
                    New Orleans, LA'\002"
            return -1
        } elseif {![validuser $hand]} {
            adduser $nick
            setuser $nick HOSTS [maskhost [getchanhost $nick] 
            chattr $nick -hp
            putlog "weather::set_location added user: $nick with host: $mask"
        }

        setuser $hand XTRA weather.location $location
        setuser $hand XTRA weather.units $units

        if {$units eq "0"} {
            set units "metric"
        } elseif {$units eq "1"} {
            set units "imperial"
        } elseif {$units eq "2"} {
            set units "metric & imperial"
        }

        putlog  "$nick set their default location to $location."

        set location_info [dict create location $location units $units]
        return $location_info    
    }

    proc _get_help {nick} {
        putlog "weather::_get_help called"
        puthelp "PRIVMSG $nick :Commands:"
        puthelp "PRIVMSG $nick :.wz <location> - Show current weather. <location> is\
                optional depending if you have your weather set to bot."
        puthelp "PRIVMSG $nick :.wzf <location> - Show a 5 day forecast. <location> is\
                 optional."
        puthelp "PRIVMSG $nick :.set 0-2 <location> - Set a default location. Units\
                must be specified from 0-2 where 0 = metric, 1 = imperial and 2 = both.\
                i.e. \".set 2 New Orleans, LA\" would spam both unit types for New Orleans."
    }
}
