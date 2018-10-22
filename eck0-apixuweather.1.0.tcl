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
#                       !wl  
#                           can be 0 for Metric, 1 for Imperial
#                       !w 
#                           Grabs current weather in location. If no location is suuplied will
#                           try to use users saved location
#                       !wf 
#                           Same as !w but provides a 3 day forecast
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
    # Default units for script
    variable unit "imperial"
    # Set your apikey here
    variable apikey "<insert-your-key-here>"
    # Set to 1 (true by default) if you want all help info and set weather responses
    # to use PM and notify. Set to 0 if you want it all in the channel.
    variable private 0

    bind pub - .set weather::set_location
    bind msg - .set weather::set_location
    bind pub - .wz weather::current_weather
    bind pub - .wzf weather::forecast


    proc current_weather {nick uhost hand chan text} {
        set text [string trim $text]

        if {$text eq "--help" || $text eq "-h"} {
            weather::_get_help
            return
        }

        if {$text eq ""} {
            # Checks to see if a user has a location set
            set userinfo [_get_userinfo $nick $hand $chan]

            if {$userinfo eq -1} {
                return
            } else {
                puthelp "PRIVMSG $chan :Userinfo is [string [dict get $userinfo location]]"
            }
        }

        
    }

    proc forecast {nick uhost hand chan text} {
        set text [string trim $text]

        if {$text eq "--help" || $text eq "-h"} {
            weather::_get_help
            return
        }
    }

    proc set_location {nick uhost hand chan text} {
        set text [string trim $text]

        if {$text eq "--help" || $text eq "-h"} {
            weather::_get_help
            return
        }
    }

    proc _get_userinfo {nick hand chan} {
        putlog "weather::_getuserinfo looking up user location and units"
        set location [getuser $hand XTRA weather.location]
        set units [getuser $hand XTRA weather.units]
        set userinfo [dict create location $location units $units]

        if {[string length [dict get $userinfo location]] eq 0} {
            putlog "weather::_getusuerinfo did not find info set for $nick"            
            if {$::weather::private ne 0} {
                puthelp "NOTICE $nick :Did you want the weather for a specific location? \
                        Or please PM me with the \".set\" command to set a default location."
            } else {
                puthelp "PRIVMSG $chan :No location set or use \".wz <location>\""
            }
            return -1
        }
 
       return $userinfo 
    }

    proc _get_xml {location type} {
        
    }

    proc _get_help {} {

    }
}
