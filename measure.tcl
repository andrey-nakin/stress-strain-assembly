#!/usr/bin/tclsh

###############################################################################
# Stress & strain measurement assembly
# Measurement module
###############################################################################

package provide ssa::measure 1.1.1

package require math::statistics
package require measure::logger
package require measure::config
package require measure::datafile
package require measure::interop
package require measure::ranges
package require measure::measure
package require measure::listutils

package require ssa::utils 1.1.1

proc runTimeStep {} {
    global doMeasurement
    
    set step [measure::config::get prog.time.step 1000.0]
    
    while { ![measure::interop::isTerminated] } {
        set t1 [clock milliseconds]
        
        lassign [readTemp] temp tempErr tempDer
        
		lassign [readAngles] phi1 phi1Err phi2 phi2Err

		display $phi1 $phi1Err $phi2 $phi2Err $temp $tempErr $tempDer 1

        set t2 [clock milliseconds]
        after [expr int($step - ($t2 - $t1))] set doMeasurement 0
        vwait doMeasurement
        after cancel set doMeasurement 0
    }
}

set tempDerValues {}

proc runTempStep {} {
    global doMeasurement tempDerValues
    global log
    
    set step [measure::config::get prog.temp.step 1.0]
    lassign [readTemp] temp tempErr
    set prevN [expr floor($temp / $step + 0.5)]
    set prevT [expr $prevN * $step]
    
    while { ![measure::interop::isTerminated] } {
        set t [clock milliseconds]
    
        lassign [readTemp] temp tempErr tempDer
        measure::listutils::lappend tempDerValues $tempDer 10 
        
		lassign [readAngles] phi1 phi1Err phi2 phi2Err

        if { $doMeasurement
            || $temp > $prevT && $temp > [expr ($prevN + 1) * $step]  \
            || $temp < $prevT && $temp < [expr ($prevN - 1) * $step] } {

			display $phi1 $phi1Err $phi2 $phi2Err $temp $tempErr $tempDer 1
            
            set prevT [expr floor($temp / $step + 0.5) * $step]
            set prevN [expr floor($temp / $step + 0.5)]
        } else {
			display $phi1 $phi1Err $phi2 $phi2Err $temp $tempErr $tempDer 0
        } 

        set der [math::statistics::mean $tempDerValues]
        set delay [expr 0.05 * $step / (abs($der) / 60000.0)]
        set delay [expr min($delay, 1000)]
        set delay [expr int($delay - ([clock milliseconds] - $t))]
        if { $delay > 50 } {
            after $delay set doMeasurement 0
            vwait doMeasurement
            after cancel set doMeasurement 0
        }
    }
}

proc runManual {} {
    global doMeasurement

    while { ![measure::interop::isTerminated] } {
        lassign [readTemp] temp tempErr tempDer
        
		lassign [readAngles] phi1 phi1Err phi2 phi2Err

		display $phi1 $phi1Err $phi2 $phi2Err $temp $tempErr $tempDer $doMeasurement
        
        after 500 set doMeasurement 0
        vwait doMeasurement
        after cancel set doMeasurement 0
    }
}

proc applySettings { lst } {
	global settings

	array set settings $lst
}

proc makeMeasurement {} {
    global doMeasurement
    
    set doMeasurement 1
}

###############################################################################
# Entry point
###############################################################################

# declare measurement thread
set ssa::isMeasurement 1

set log [measure::logger::init measure]

measure::interop::registerFinalization { finish }

measure::config::read

validateSettings

setup

measure::datafile::create $settings(result.fileName) $settings(result.format) $settings(result.rewrite) {
	"Date/Time" "T (K)" "+/- (K)" "dT/dt (K/min)" "phi1" "+/-" "phi2" "+/-" "gamma (%)" "+/- (%)" "tau (Pa)" "+/- (Pa)"
} "$settings(result.comment), [measure::measure::dutParams]"

readTemp

set doMeasurement 0
if { $settings(prog.method) == 0 } {
    runTimeStep
} elseif { $settings(prog.method) == 1 } {
    runTempStep
} else {
    runManual
}

finish

