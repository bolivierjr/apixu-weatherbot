#!usr/bin/env tclsh

########################################################################################
# Name              apixu-weatherbot1.0.tcl
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
#                          - Grabs current weather location. If no location is
#                            given, will try to use users saved location
#
#                       .wzf <location>
#                          - Same as .wz but provides a 5 day forecast
#                       
#                       Use the --help or -h flags with any of the commands to
#                       get help with the commands and descriptions.
#
# Version           1.0 - Initial Release
#
# Notes             Grab your own api key at https://apixu.com and place it in
#                   the "apikey" variable below. Set private variable to 0 or 1
#                   if you want the set command responses in PM.
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
    # Environment variable set for the weather api from apixu.
    variable apikey $::env(WEATHER_API_KEY)
    # Number of days you want the forecast to output.
    variable forecast_days "5"
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

    ##########################
    # Public command functions
    ##########################
    proc current {nick uhost hand chan text} {
        set text [string trim $text]

        if {$text eq "--help" || $text eq "-h"} {
            _get_help $nick
            return
        }

        # Checks to see if a user has a location set
        set userinfo [_get_userinfo $nick $hand]
        if {$text eq "" && [dict exists $userinfo error]} {
            if {$::weather::private} {
                puthelp "NOTICE $nick :Did you want the weather for a specific location?\
                         Or please PM me with the \".set\" command to set a default location."
                return
            }

            puthelp "PRIVMSG $chan :No location set or use \002'.wz <location>'\002"
            return
        } elseif {[dict exists $userinfo error]} {
            set userinfo [dict create location $text units $::weather::units]
        } elseif {$text ne ""} {
            set userinfo [dict create location $text units [dict get $userinfo units]]
        }

        set location [dict get $userinfo location]
        if {[catch {set json_data [_get_weather_data $location "current" $chan]} errormsg]} {
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
        if {$text eq "" && [dict exists $userinfo error]} {
            if {$::weather::private} {
                puthelp "NOTICE $nick :Did you want the weather for a specific location?\
                         Or please PM me with the \".set\" command to set a default location."
                return
            }

            puthelp "PRIVMSG $chan :No location set or use \002'.wzf <location>'\002"
            return
        } elseif {[dict exists $userinfo error]} {
            set userinfo [dict create location $text units $::weather::units]
        } elseif {$text ne ""} {
            set userinfo [dict create location $text units [dict get $userinfo units]]
        }

        set location [dict get $userinfo location]
        if {[catch {set json_data [_get_weather_data $location "forecast" $chan]} errormsg]} {
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
            # If $private is set to 1, send a PM
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

    ###################################
    # Private message command functions
    ###################################
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

    #######################
    # Helper functions
    #######################
    proc _get_userinfo {nick hand} {
        # Looks up userinfo in the XTRA of userfile.
        #
        # Args:
        #   nick(string) - Users nick.
        #   hand(string) - Users handle.
        #
        # Returns:
        #   (dict) - Returns userinfo or error if user not found.
        #
        putlog "weather::_getuserinfo looking up user location and units"
        set location [getuser $hand XTRA weather.location]
        set units [getuser $hand XTRA weather.units]
        set userinfo [dict create location $location units $units]

        if {![string length [dict get $userinfo location]]} {
            putlog "weather::_getusuerinfo did not find info set for $nick"            
            return [dict create error "Did not find a user"]
        }
 
       return $userinfo 
    }

    proc _get_weather_data {location type chan} {
        # Fetches JSON data from the apixu API.
        #
        # Args:
        #   location(string) - Users location given.
        #   type(string) - Current weather or forecast called.
        #
        # Returns:
        #   (dict) Returns json data received from the api and
        #          converted to a dict.
        #
        putlog "weather::_get_weather_datawas called"
        set query [::http::formatQuery key $::weather::apikey q $location]
        set url "$::weather::base_url/$type.json?$query"
        if {$type ne "current"} {
            set url "$::weather::base_url/$type.json?$query&days=$::weather::forecast_days"
        }

        putlog "weather::_get_weather_data getting data from $url"
        set token [::http::geturl $url -timeout 750]
        set status [::http::status $token]

        # If a timeout occurs to the api request, retry up to
        # max_retries with backoff. Default backoff set to 1000ms.
        if {$status eq "timeout"} {
            ::http::cleanup $token
            set retry 1
            set max_retries 10
            set backoff 1000

            while {$retry <= $max_retries} {
                set token [::http::geturl $url -timeout 750]
                set status [::http::status $token]

                if {$retry eq 3} {
                    putquick "PRIVMSG $chan :This is taking a bit, please wait."
                }

                if {$status eq "timeout"} {
                    ::http::cleanup $token
                    if {$retry eq $max_retries} {
                        error "The APIXU api has timed out. Try again later."
                    }

                    incr retry
                    after $backoff
                    continue
                }

                break
            }
        }

        set response_code [::http::ncode $token]
        set json [::http::data $token]
        # Converts the json data to a dict
        set data [::json::json2dict $json]

        # If data returns back an error, show the message
        if {[dict exists $data error]} {
            ::http::cleanup $token
            putlog [dict get $data error message]
            error [dict get $data error message]
        }

        if {![string length $data]} {
            ::http::cleanup $token
            putlog "returned no data"
            putlog "status: $status, code: $response_code"
            error "Bot's broked. Tell the admin to MAEK FEEKS!"
        }

        if {$status eq "ok" && $response_code eq 200} {
            ::http::cleanup $token
            putlog "status: $status, code: $response_code"
            return $data
        }
    }

    proc _json_parse {data userinfo type} {
        # Converts json to a dict and parses it to display weather.
        #
        # Args:
        #   json(string) - Data received from api.
        #   userinfo(dict) - Userinfo with location and units set.
        #   type(string) - Current weather or forecast called.
        #
        # Returns:
        #   (string) - Returns the string of weather to be displayed to user.
        #
        set units [dict get $userinfo units]
        set city [dict get $data location name]
        set region [dict get $data location region]

        # If the region is not found or every city not in USA/CA, use
        # the country instead of region.
        set ca "Canada"
        set usa "United States of America"
        set country [dict get $data location country]
        if {$country eq "USA"} {
            set country "United States of America"
        }
        if {![string length $region] || !($usa eq $country || $ca eq $country)} {
            set region $country
        }

        # Check to see if querying current or forecast weather and nested
        # switch to check whether units are 0, 1, or 2 for metric, imperial
        # or both. Return given string of data to display to the user.
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
                    set date [dict get $forecast date]
                    # Converts date to the day of the week.
                    set dayname [clock format [clock scan $date] -format %a]
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
        # Sets a users location and units in the eggdrop userfile.
        #
        # Args:
        #   nick(string) - Users nick.
        #   ushost(string) - Users username and host.
        #   hand(string) - Users handle.
        #   text(string) - Units and location to be set.
        #
        # Returns:
        #   (dict) - Returns the userinfo(units and location)
        #            that was set to the bot.
        #
        putlog "weather::location was called"
        putlog "nick: $nick, uhost: $uhost, hand: $hand is trying to set location"
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

        # Sets the location and units to each user
        # in the eggdrop userfile.
        setuser $hand XTRA weather.location $location
        setuser $hand XTRA weather.units $units

        switch $units {
            "0" {
                set units "metric"
            }
            "1" {
                set units "imperial"
            }
            "2" {
                set units "metric & imperial"
            }
        }

        putlog  "$nick set their default location to $location."

        set location_info [dict create location $location units $units]
        return $location_info    
    }

    proc _get_help {nick} {
        # Help section of the script called by user.
        #
        # Args:
        #   nick(string) - Users nick.
        #
        # Returns:
        #   (string) - Returns the list of commands and
        #              description/examples of each one.
        #
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
