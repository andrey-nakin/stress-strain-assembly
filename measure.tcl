#!/usr/bin/tclsh

###############################################################################
# Stress & strain measurement assembly
# Measurement module
###############################################################################

package provide ssa::measure 1.1.0

package require math::statistics
package require measure::logger
package require measure::config
package require measure::datafile
package require measure::interop
package require measure::ranges
package require measure::measure
package require measure::listutils

package require ssa::utils 1.1.0

###############################################################################
# \u041A\u043E\u043D\u0441\u0442\u0430\u043D\u0442\u044B
###############################################################################

###############################################################################
# \u041F\u043E\u0434\u043F\u0440\u043E\u0433\u0440\u0430\u043C\u043C\u044B
###############################################################################

# \u041F\u0440\u043E\u0438\u0437\u0432\u043E\u0434\u0438\u0442 \u0440\u0435\u0433\u0438\u0441\u0442\u0440\u0430\u0446\u0438\u044E \u0434\u0430\u043D\u043D\u044B\u0445 \u043F\u043E \u0437\u0430\u0434\u0430\u043D\u043D\u043E\u043C\u0443 \u0432\u0440\u0435\u043C\u0435\u043D\u043D\u043E\u043C\u0443 \u0448\u0430\u0433\u0443
proc runTimeStep {} {
    global doMeasurement
    
    set step [measure::config::get prog.time.step 1000.0]
    
    # \u0412\u044B\u043F\u043E\u043B\u043D\u044F\u0435\u043C \u0446\u0438\u043A\u043B \u043F\u043E\u043A\u0430 \u043D\u0435 \u043F\u0440\u0435\u0440\u0432\u0451\u0442 \u043F\u043E\u043B\u044C\u0437\u043E\u0432\u0430\u0442\u0435\u043B\u044C
    while { ![measure::interop::isTerminated] } {
        set t1 [clock milliseconds]
        
        # \u0441\u0447\u0438\u0442\u044B\u0432\u0430\u0435\u043C \u0442\u0435\u043C\u043F\u0435\u0440\u0430\u0442\u0443\u0440\u0443
        lassign [readTemp] temp tempErr tempDer
        
        # \u0441\u0447\u0438\u0442\u044B\u0432\u0430\u0435\u043C \u0443\u0433\u043B\u044B
		lassign [readAngles] phi1 phi1Err phi2 phi2Err

		# \u0432\u044B\u0432\u043E\u0434\u0438\u043C \u0440\u0435\u0437\u0443\u043B\u044C\u0442\u0430\u0442\u044B \u043D\u0430 \u044D\u043A\u0440\u0430\u043D\u0435
		display $phi1 $phi1Err $phi2 $phi2Err $temp $tempErr $tempDer 1

        set t2 [clock milliseconds]
        after [expr int($step - ($t2 - $t1))] set doMeasurement 0
        vwait doMeasurement
        after cancel set doMeasurement 0
    }
}

# \u041F\u0440\u043E\u0438\u0437\u0432\u043E\u0434\u0438\u0442 \u0440\u0435\u0433\u0438\u0441\u0442\u0440\u0430\u0446\u0438\u044E \u0434\u0430\u043D\u043D\u044B\u0445 \u043F\u043E \u0437\u0430\u0434\u0430\u043D\u043D\u043E\u043C\u0443 \u0442\u0435\u043C\u043F\u0435\u0440\u0430\u0442\u0443\u0440\u043D\u043E\u043C\u0443 \u0448\u0430\u0433\u0443
set tempDerValues {}

proc runTempStep {} {
    global doMeasurement tempDerValues
    global log
    
    set step [measure::config::get prog.temp.step 1.0]
    lassign [readTemp] temp tempErr
    set prevN [expr floor($temp / $step + 0.5)]
    set prevT [expr $prevN * $step]
    
    # \u0412\u044B\u043F\u043E\u043B\u043D\u044F\u0435\u043C \u0446\u0438\u043A\u043B \u043F\u043E\u043A\u0430 \u043D\u0435 \u043F\u0440\u0435\u0440\u0432\u0451\u0442 \u043F\u043E\u043B\u044C\u0437\u043E\u0432\u0430\u0442\u0435\u043B\u044C
    while { ![measure::interop::isTerminated] } {
        # \u0442\u0435\u043A\u0443\u0449\u0435\u0435 \u0432\u0440\u0435\u043C\u044F
        set t [clock milliseconds]
    
        # \u0441\u0447\u0438\u0442\u044B\u0432\u0430\u0435\u043C \u0442\u0435\u043C\u043F\u0435\u0440\u0430\u0442\u0443\u0440\u0443
        lassign [readTemp] temp tempErr tempDer
        measure::listutils::lappend tempDerValues $tempDer 10 
        
        # \u0441\u0447\u0438\u0442\u044B\u0432\u0430\u0435\u043C \u0443\u0433\u043B\u044B
		lassign [readAngles] phi1 phi1Err phi2 phi2Err

        if { $doMeasurement
            || $temp > $prevT && $temp > [expr ($prevN + 1) * $step]  \
            || $temp < $prevT && $temp < [expr ($prevN - 1) * $step] } {

			# \u0432\u044B\u0432\u043E\u0434\u0438\u043C \u0440\u0435\u0437\u0443\u043B\u044C\u0442\u0430\u0442\u044B \u043D\u0430 \u044D\u043A\u0440\u0430\u043D\u0435
			display $phi1 $phi1Err $phi2 $phi2Err $temp $tempErr $tempDer 1
            
            set prevT [expr floor($temp / $step + 0.5) * $step]
            set prevN [expr floor($temp / $step + 0.5)]
        } else {
			# \u0432\u044B\u0432\u043E\u0434\u0438\u043C \u0440\u0435\u0437\u0443\u043B\u044C\u0442\u0430\u0442\u044B \u043D\u0430 \u044D\u043A\u0440\u0430\u043D\u0435 \u0431\u0435\u0437 \u0437\u0430\u043F\u0438\u0441\u0438 \u0432 \u0444\u0430\u0439\u043B
			display $phi1 $phi1Err $phi2 $phi2Err $temp $tempErr $tempDer 0
        } 

        # \u043E\u043F\u0440\u0435\u0434\u0435\u043B\u0438\u043C, \u043A\u0430\u043A\u0443\u044E \u043F\u0430\u0443\u0437\u0443 \u043D\u0443\u0436\u043D\u043E \u0432\u044B\u0434\u0435\u0440\u0436\u0430\u0442\u044C \u0432 \u0437\u0430\u0432\u0438\u0441\u0438\u043C\u043E\u0441\u0442\u0438 \u043E\u0442 dT/dt
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

# \u041F\u0440\u043E\u0438\u0437\u0432\u043E\u0434\u0438\u0442 \u0440\u0435\u0433\u0438\u0441\u0442\u0440\u0430\u0446\u0438\u044E \u0434\u0430\u043D\u043D\u044B\u0445 \u043F\u043E \u043A\u043E\u043C\u0430\u043D\u0434\u0430\u043C \u043E\u043F\u0435\u0440\u0430\u0442\u043E\u0440\u0430
proc runManual {} {
    global doMeasurement

    # \u0412\u044B\u043F\u043E\u043B\u043D\u044F\u0435\u043C \u0446\u0438\u043A\u043B \u043F\u043E\u043A\u0430 \u043D\u0435 \u043F\u0440\u0435\u0440\u0432\u0451\u0442 \u043F\u043E\u043B\u044C\u0437\u043E\u0432\u0430\u0442\u0435\u043B\u044C
    while { ![measure::interop::isTerminated] } {
        # \u0441\u0447\u0438\u0442\u044B\u0432\u0430\u0435\u043C \u0442\u0435\u043C\u043F\u0435\u0440\u0430\u0442\u0443\u0440\u0443
        lassign [readTemp] temp tempErr tempDer
        
        # \u0441\u0447\u0438\u0442\u044B\u0432\u0430\u0435\u043C \u0443\u0433\u043B\u044B
		lassign [readAngles] phi1 phi1Err phi2 phi2Err

		# \u0432\u044B\u0432\u043E\u0434\u0438\u043C \u0440\u0435\u0437\u0443\u043B\u044C\u0442\u0430\u0442\u044B \u043D\u0430 \u044D\u043A\u0440\u0430\u043D\u0435
		display $phi1 $phi1Err $phi2 $phi2Err $temp $tempErr $tempDer $doMeasurement
        
        after 500 set doMeasurement 0
        vwait doMeasurement
        after cancel set doMeasurement 0
    }
}

###############################################################################
# \u041E\u0431\u0440\u0430\u0431\u043E\u0442\u0447\u0438\u043A\u0438 \u0441\u043E\u0431\u044B\u0442\u0438\u0439
###############################################################################

# \u041A\u043E\u043C\u0430\u043D\u0434\u0430 \u043F\u0440\u043E\u0447\u0438\u0442\u0430\u0442\u044C \u043F\u043E\u0441\u043B\u0435\u0434\u043D\u0438\u0435 \u043D\u0430\u0441\u0442\u0440\u043E\u0439\u043A\u0438
proc applySettings { lst } {
	global settings

	array set settings $lst
}

# \u041F\u0440\u043E\u0438\u0437\u0432\u0435\u0441\u0442\u0438 \u043E\u0447\u0435\u0440\u0435\u0434\u043D\u043E\u0435 \u0438\u0437\u043C\u0435\u0440\u0435\u043D\u0438\u0435
proc makeMeasurement {} {
    global doMeasurement
    
    set doMeasurement 1
}

###############################################################################
# \u041D\u0430\u0447\u0430\u043B\u043E \u0440\u0430\u0431\u043E\u0442\u044B
###############################################################################

# declare measurement thread
set ssa::isMeasurement 1

# \u0418\u043D\u0438\u0446\u0438\u0430\u043B\u0438\u0437\u0438\u0440\u0443\u0435\u043C \u043F\u0440\u043E\u0442\u043E\u043A\u043E\u043B\u0438\u0440\u043E\u0432\u0430\u043D\u0438\u0435
set log [measure::logger::init measure]

# \u042D\u0442\u0430 \u043A\u043E\u043C\u0430\u043D\u0434\u0430 \u0431\u0443\u0434\u0435\u0442 \u0432\u044B\u0437\u0432\u0430\u0430\u0442\u044C\u0441\u044F \u0432 \u0441\u043B\u0443\u0447\u0430\u0435 \u043F\u0440\u0435\u0436\u0434\u0435\u0432\u0440\u0435\u043C\u0435\u043D\u043D\u043E\u0439 \u043E\u0441\u0442\u0430\u043D\u043E\u0432\u043A\u0438 \u043F\u043E\u0442\u043E\u043A\u0430
measure::interop::registerFinalization { finish }

# \u0427\u0438\u0442\u0430\u0435\u043C \u043D\u0430\u0441\u0442\u0440\u043E\u0439\u043A\u0438 \u043F\u0440\u043E\u0433\u0440\u0430\u043C\u043C\u044B
measure::config::read

# \u041F\u0440\u043E\u0432\u0435\u0440\u044F\u0435\u043C \u043F\u0440\u0430\u0432\u0438\u043B\u044C\u043D\u043E\u0441\u0442\u044C \u043D\u0430\u0441\u0442\u0440\u043E\u0435\u043A
validateSettings

# \u041F\u0440\u043E\u0438\u0437\u0432\u043E\u0434\u0438\u043C \u043F\u043E\u0434\u043A\u043B\u044E\u0447\u0435\u043D\u0438\u0435 \u043A \u0443\u0441\u0442\u0440\u043E\u0439\u0441\u0442\u0432\u0430\u043C \u0438 \u0438\u0445 \u043D\u0430\u0441\u0442\u0440\u043E\u0439\u043A\u0443
setup

# \u0421\u043E\u0437\u0434\u0430\u0451\u043C \u0444\u0430\u0439\u043B\u044B \u0441 \u0440\u0435\u0437\u0443\u043B\u044C\u0442\u0430\u0442\u0430\u043C\u0438 \u0438\u0437\u043C\u0435\u0440\u0435\u043D\u0438\u0439
measure::datafile::create $settings(result.fileName) $settings(result.format) $settings(result.rewrite) {
	"Date/Time" "T (K)" "+/- (K)" "dT/dt (K/min)" "phi1" "+/-" "phi2" "+/-" "gamma (%)" "+/- (%)" "tau (Pa)" "+/- (Pa)"
} "$settings(result.comment), [measure::measure::dutParams]"

###############################################################################
# \u041E\u0441\u043D\u043E\u0432\u043D\u043E\u0439 \u0446\u0438\u043A\u043B \u0438\u0437\u043C\u0435\u0440\u0435\u043D\u0438\u0439
###############################################################################

readTemp

set doMeasurement 0
if { $settings(prog.method) == 0 } {
    runTimeStep
} elseif { $settings(prog.method) == 1 } {
    runTempStep
} else {
    runManual
}

###############################################################################
# \u0417\u0430\u0432\u0435\u0440\u0448\u0435\u043D\u0438\u0435 \u0438\u0437\u043C\u0435\u0440\u0435\u043D\u0438\u0439
###############################################################################

finish

