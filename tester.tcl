#!/usr/bin/tclsh

###############################################################################
# Stress & strain measurement assembly
# Tester module
###############################################################################

package provide ssa::tester 1.1.1

package require measure::logger
package require measure::config
package require measure::interop
package require measure::sigma
package require measure::datafile
package require measure::measure
package require measure::format
package require ssa::utils

set DELAY 1000

proc run {} {
    global DELAY log

	setup

    while { ![measure::interop::isTerminated] } {

        lassign [readTemp] temp tempErr tempDer
        
		lassign [readAngles] phi1 phi1Err phi2 phi2Err

		display $phi1 $phi1Err $phi2 $phi2Err $temp $tempErr $tempDer

        after $DELAY
    }
}

###############################################################################
# Entry point
###############################################################################

set log [measure::logger::init tester]

measure::config::read

validateSettings

measure::interop::registerFinalization { finish }

run

finish

