#!usr/bin/env tclsh

########################################################################################
# Name              apixu-weatherbot-1.0.tcl
#
# Author            Bruce Olivier <bolivierjr@gmail.com>
#
# Description       Uses the Apixu weather API to grab the data.
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
    package require json
    package require tdom
    package require http
    package require tls

    # To be able to query APIs that use https
    http::register https 443 [list tls::socket -tls1 1 -ssl2 0 -ssl3 0]

    setudef flag weather-apixu
    # Default units for weather output. 0 for metric, 1 for imperial, 2 for both.
    variable units "1"
    variable base_url "https://api.apixu.com/v1"
    # Set your apikey here
    variable apikey "<insert-your-key-here>"
    # Set to 1 (0 by default) if you want set weather responses
    # to use PM/notify. Set to 0 if you want it all in the channel.
    variable private 0

    # Public channel command bindings
    bind pub - .wz weather::current
    bind pub - .wzf weather::forecast
    bind pub - .set weather::location

    # Private message command bindings
    bind msg - .wz weather::pm_current
    bind msg - .wzf weather::pm_forecast
    bind msg - .set weather::pm_location
    # Public command functions
    proc current {nick uhost hand chan text} {
        set text [string trim $text]

        if {$text eq "--help" || $text eq "-h"} {
            _get_help $nick
            return
        }

        # Checks to see if a user has a location set
        set userinfo [_get_userinfo $nick $hand]
        if {$text eq "" && $userinfo eq -1} {
            if {$::weather::private} {
                puthelp "NOTICE $nick :Did you want the weather for a specific location?\
                         Or please PM me with the \".set\" command to set a default location."
                return
            }

            puthelp "PRIVMSG $chan :No location set or use \002'.wz <location>'\002"
            return
        } elseif {$userinfo eq -1} {
            set userinfo [dict create location $text units $::weather::units]
        } elseif {$text ne ""} {
            set userinfo [dict create location $text units [dict get $userinfo units]]
        }

        set location [dict get $userinfo location]
        if {[catch {set json_data [_get_json $location "current"]} errormsg]} {
            puthelp "PRIVMSG $chan :$errormsg"
            return
        }

        if {[catch {set current_weather [_json_parse $json_data $userinfo "current"]} errormsg]} {
            puthelp "PRIVMSG $chan :$errormsg"
            return
        }

        puthelp "PRIVMSG $chan :$current_weather"
    }

    proc forecast {nick uhost hand chan text} {
        set text [string trim $text]

        if {$text eq "--help" || $text eq "-h"} {
            _get_help $nick
            return
        }


        # Checks to see if a user has a location set
        set userinfo [_get_userinfo $nick $hand]
        if {$text eq "" && $userinfo eq -1} {
            if {$::weather::private} {
                puthelp "NOTICE $nick :Did you want the weather for a specific location?\
                         Or please PM me with the \".set\" command to set a default location."
                return
            }

            puthelp "PRIVMSG $chan :No location set or use \002'.wzf <location>'\002"
            return
        } elseif {$userinfo eq -1} {
            set userinfo [dict create location $text units $::weather::units]
        } elseif {$text ne ""} {
            set userinfo [dict create location $text units [dict get $userinfo units]]
        }

        set location [dict get $userinfo location]
        if {[catch {set json_data [_get_json $location "forecast"]} errormsg]} {
            puthelp "PRIVMSG $chan :$errormsg"
            return
        }

        if {[catch {set forecastdays [_json_parse $json_data $userinfo "forecast"]} errormsg]} {
            puthelp "PRIVMSG $chan :$errormsg"
            return
        }

        puthelp "PRIVMSG $chan :$forecastdays"
    }

    proc location {nick uhost hand chan text} {
        set $text [string trim $text]

        if {$text eq "--help" || $text eq "-h"} {
            _get_help $nick
            return
        } elseif {$::weather::private} {
            putlog "::weather::private set to private. Use PM instead."
            puthelp "PRIVMSG $nick :Please private message me to set your location.\ 
                     i.e. \002'.set 1 <location>'\002 to set your location and use imperial\
                     units."
            return
        }

        if {[catch {set location_info [_set_location $nick $uhost $hand $text]} errormsg]} {
            puthelp "PRIVMSG $chan :$errormsg"
            return
        }

        puthelp "PRIVMSG $chan :Default weather location for \002$nick\002 set to\
                 \002[dict get $location_info location]\002 and units set to\
                 \002[dict get $location_info units]\002\."
    }

    # Private message command functions
    proc pm_current {nick uhost hand text} {
        set text [string trim $text]

        if {$text eq "--help" || $text eq "-h"} {
            _get_help $nick
        }
    }

    proc pm_forecast {nick uhost hand text} {
        set text [string trim $text]

        if {$text eq "--help" || $text eq "-h"} {
            _get_help $nick
        }
    }

    proc pm_location {nick uhost hand text} {
        set text [string trim $text]

        if {$text eq "--help" || $text eq "-h"} {
            _get_help $nick
            return
        }

        if {[catch {set location_info [_set_location $nick $uhost $hand $text]} errormsg]} {
            puthelp "PRIVMSG $nick :$errormsg"
            return 
        }

        puthelp "PRIVMSG $nick :Default weather location for \002$nick\002 set to\
                 \002[dict get $location_info location]\002 and units set to\
                 \002[dict get $location_info units]\002\."
    }

    # Helper functions below
    proc _get_userinfo {nick hand} {
        putlog "weather::_getuserinfo looking up user location and units"
        set location [getuser $hand XTRA weather.location]
        set units [getuser $hand XTRA weather.units]
        set userinfo [dict create location $location units $units]

        if {![string length [dict get $userinfo location]]} {
            putlog "weather::_getusuerinfo did not find info set for $nick"            
            return -1
        }
 
       return $userinfo 
    }

    proc _get_json {location type} {
        putlog "weather::_get_json was called"

        if {[regexp {[^\w., ]} $location]} {
            error "No matching location found"
        }

        regsub -all -- { } $location {%20} location

        set url "$::weather::base_url/$type.json?key=$::weather::apikey&q=$location"
        if {$type ne "current"} {
            set url "$::weather::base_url/$type.json?key=$::weather::apikey&q=$location&days=5"
        }

        putlog "weather::_get_json getting data from $url"
        if {[catch {set token [::http::geturl $url -timeout 10000]} errormsg]} {
            putlog "::http::geturl Error: $errormsg"
            error "No matching location found"
        }

        set data [::http::data $token]
        set status [::http::status $token]
        set ncode [::http::ncode $token]

        if {$status eq "ok" || $ncode eq 200} {
            ::http::cleanup $token
            putlog "status: $status, code: $ncode"
            return $data
        }

        if {![string length $data]} {
            ::http::cleanup $token
            putlog "returned no data"
            error "Bot's broked. Tell eck0 to MAEK FEEKS!"
        }
    }

    proc _json_parse {json userinfo type} {
        set data [::json::json2dict $json]

        if {[dict exists $data error]} {
            putlog [dict get $data error message]
            error [dict get $data error message]
        }

        set units [dict get $userinfo units]
        set city [dict get $data location name]
        set region [dict get $data location region]
        if {[string length $region]} {
            set region [dict get $data location country]
        }

        switch $type {
            "current" {
                set condition [dict get $data current condition text]
                foreach key {temp_f temp_c wind_mph wind_kph wind_dir humidity feelslike_f feelslike_c} {
                    set $key [dict get $data current $key]
                }

                switch $units {
                    "0" {
                        return "\002$city, $region\002 - \002Conditions:\002 $condition - \002Temp:\
                                \002$temp_c\C - \002Feelslike:\002 $feelslike_c\C - \002Humidity:\
                                \002$humidity% - \002Wind:\002 [expr $wind_kph <= 8 ? \"Calm\" :\
                                \"$wind_dir at $wind_kph\kph\"]"
                    }

                    "1" {
                        return "\002$city, $region\002 - \002Conditions:\002 $condition - \002Temp:\
                                \002$temp_f\F - \002Feelslike:\002 $feelslike_f\F - \002Humidity:\
                                \002$humidity% - \002Wind:\002 [expr $wind_mph <= 5 ? \"Calm\" :\
                                \"$wind_dir at $wind_mph\mph\"]"
                    }

                    "2" {
                        return "\002$city, $region\002 - \002Conditions:\002 $condition - \002Temp:\
                                \002$temp_f\F ($temp_c\C) - \002Feelslike:\002 $feelslike_f\F\
                                ($feelslike_c\C) - \002Humidity: \002$humidity% - \002Wind:\002\
                                [expr $wind_mph <= 5 ? \"Calm\" : \"$wind_dir at $wind_mph\mph\
                                ($wind_kph\kph)\"]"
                    }
                }
            }

            "forecast" {
                set forecasts [dict get $data forecast forecastday]
                set spam "Forecast for \002$city, $region\002"

                foreach forecast $forecasts {
                    set date_epoch [dict get $forecast date_epoch]
                    set dayname [clock format $date_epoch -format "%a"]
                    set condition [dict get $forecast day condition text]
                    set maxtemp_c [dict get $forecast day maxtemp_c]
                    set mintemp_c [dict get $forecast day mintemp_c]
                    set maxtemp_f [dict get $forecast day maxtemp_f]
                    set mintemp_f [dict get $forecast day mintemp_f]

                    switch $units {
                        "0" {
                            append spam " - \002$dayname:\002 $condition (High: $maxtemp_c\C\
                                         Low: $mintemp_c\C)"
                            continue
                        }

                        "1" {
                            append spam " - \002$dayname:\002 $condition (High: $maxtemp_f\F\
                                         Low: $mintemp_f\F)"
                            continue
                        }

                        "2" {
                            append spam " - \002$dayname:\002 $condition (High: $maxtemp_f\F/$maxtemp_c\C\
                                         Low: $mintemp_f\F/$mintemp_c\C)"
                            continue
                        }
                    }
                }

                return $spam
            }
        }
    }

    proc _set_location {nick uhost hand text} {
        putlog "weather::location was called"
        putlog "nick: $nick, uhost: $uhost, hand: $hand is trying to set location"
        if {[regexp {[^\w., ]} $text]} {
            putlog "weather::_set_location caught illegal characters"
            error "What are you doing? Act normal!"
        }

        set units [string index $text 0]
        set location [string range $text 2 end]

        if {!($units eq "0" || $units eq "1" || $units eq "2")} {
            putlog "$nick set units to an invalid number."
            error "Units must be specified from 0-2 where 0 = metric, 1 = imperial and 2\
                   = both. i.e. \002'.set 2 New Orleans, LA'\002 would spam both unit\
                   types for New Orleans."
        } elseif {![string length $location]} {
            putlog "$nick gave an invalid location"
            error "Must supply a location to be set. i.e. \002'set 1\
                    New Orleans, LA'\002"
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

putlog "apixu-weatherbot1.0.tcl (https://github.com/bolivierjr/apixu-weatherbot) loaded"
