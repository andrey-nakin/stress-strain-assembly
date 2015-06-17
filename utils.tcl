#!/usr/bin/tclsh

###############################################################################
# Stress & strain measurement assembly
# Common utils
###############################################################################

package provide ssa::utils 1.1.0
namespace eval ssa { }

package require measure::listutils
package require measure::math
package require measure::sigma
package require measure::expr
package require hardware::owen::trm201::modbus
package require hardware::skbis::lir916
package require Thread

###############################################################################
# Global constants & variables
###############################################################################

# list of event variable labels
set ssa::EVENT_WHAT { "\u03C61 (\u0433\u0440\u0430\u0434)" "\u03C62 (\u0433\u0440\u0430\u0434)" "\u0414\u0435\u0444\u043E\u0440\u043C\u0430\u0446\u0438\u044F \u03B3 (%)" "\u041D\u0430\u043F\u0440\u044F\u0436\u0435\u043D\u0438\u0435 \u03C4 (\u041C\u041F\u0430)"  "\u0422\u0435\u043C\u043F\u0435\u0440\u0430\u0442\u0443\u0440\u0430 (\u041A)" }

# list of event variable names
set ssa::EVENT_VAR { phi1 phi2 gamma tau temp }

# list of event criteria
set ssa::EVENT_RELATION { "\u0411\u043E\u043B\u044C\u0448\u0435, \u0447\u0435\u043C" "\u041C\u0435\u043D\u044C\u0448\u0435, \u0447\u0435\u043C" }

# list of event criteria expressions
set ssa::EVENT_RELATION_EXPR { ">=" "<=" }

# list of event sounds
set ssa::EVENT_SOUND { SystemAsterisk SystemExclamation SystemExit SystemHand SystemNotification SystemQuestion }

# max number of events
set ssa::MAX_EVENTS 10

# true when thread is working in measurement mode
set ssa::isMeasurement 0

###############################################################################
# Package-private constants & variables
###############################################################################

# \u0427\u0438\u0441\u043B\u043E \u0438\u0437\u043C\u0435\u0440\u0435\u043D\u0438\u0439, \u043F\u043E \u043A\u043E\u0442\u043E\u0440\u044B\u043C \u043E\u043F\u0440\u0435\u0434\u0435\u043B\u044F\u0435\u0442\u0441\u044F \u043F\u0440\u043E\u0438\u0437\u0432\u043E\u0434\u043D\u0430\u044F dT/dt
set DERIVATIVE_READINGS 10

# Prev variable values
array set prevValues {}

###############################################################################
# Utility procedures
###############################################################################

# \u041F\u0440\u043E\u0446\u0435\u0434\u0443\u0440\u0430 \u043F\u0440\u043E\u0432\u0435\u0440\u044F\u0435\u0442 \u043F\u0440\u0430\u0432\u0438\u043B\u044C\u043D\u043E\u0441\u0442\u044C \u043D\u0430\u0441\u0442\u0440\u043E\u0435\u043A, \u043F\u0440\u0438 \u043D\u0435\u043E\u0431\u0445\u043E\u0434\u0438\u043C\u043E\u0441\u0442\u0438 \u0432\u043D\u043E\u0441\u0438\u0442 \u043F\u043E\u043F\u0440\u0430\u0432\u043A\u0438
proc validateSettings {} {
    measure::config::validate {
        result.fileName ""
        result.format TXT
        result.rewrite 1
        result.comment ""

		prog.time.step 1000
		prog.temp.step 1.0

		dut.rErr	0.0
		dut.lengthErr	0.0
		dut.momentumErr	0.0

		lir1.zero	0
		lir2.zero	0
		lir1.coeff	1.0
		lir2.coeff	1.0

		tc.correction	""
    }
	tsv::set measure method [measure::config::get measure.method 0]
}

proc calcGamma { phi1 phi1Err phi2 phi2Err } {
	global settings

	set res 0.0
	set resErr 0.0

	catch {
		set r $settings(dut.r)
		set rErr $settings(dut.rErr)
		set length $settings(dut.length)
		set lengthErr $settings(dut.lengthErr)

		set phiDiff [expr $phi1 - $phi2]
		set phiDiffErr [measure::sigma::add $phi1Err $phi2Err]

		set a [expr 1.0 * $r / $length]
		set aErr [measure::sigma::div $r $rErr $length $lengthErr]

		set res [expr $a * $phiDiff]
		set resErr [measure::sigma::mul $a $aErr $phiDiff $phiDiffErr]
	}

	set res [expr 100.0 * $res]
	set resErr [expr 100.0 * $resErr]

	return [list $res $resErr]
}

proc calcTau { phi2 phi2Err } {
	global settings

	set res 0.0
	set resErr 0.0

	catch {
		set momentum $settings(dut.momentum)
		set momentumErr $settings(dut.momentumErr)

		if { [tsv::get measure method] == 0 } {
			set s [expr sin($phi2)]
			set sErr [measure::sigma::sin $phi2 $phi2Err]
		} else {
			set s 1.0
			set sErr 0.0
		}

		set a [expr 1.5 * $momentum * $s]
		set aErr [measure::sigma::mul $momentum $momentumErr $s $sErr]

		set radius [expr 1.0e-3 * $settings(dut.r)]
		set radiusErr [expr 1.0e-3 * $settings(dut.rErr)]

		set b [expr 3.1415926535897932384 * $radius * $radius * $radius]
		set bErr [measure::sigma::pow3 $radius $radiusErr]

		set res [expr $a / $b]
		set resErr [measure::sigma::div $a $aErr $b $bErr]
	}

	return [list $res $resErr]
}

proc initLir { key } {
    return [::hardware::skbis::lir916::init \
		-com [measure::config::get -required rs485.serialPort] \
		-addr [measure::config::get -required ${key}.addr] \
		-baud [measure::config::get ${key}.baud 9600] \
		-zero [measure::config::get ${key}.zero 0] \
		-coeff [measure::config::get ${key}.coeff 1.0] \
	]
}

# \u0418\u043D\u0438\u0446\u0438\u0430\u043B\u0438\u0437\u0430\u0446\u0438\u044F \u043F\u0440\u0438\u0431\u043E\u0440\u043E\u0432
proc setup {} {
    global lir1 lir2 trm

	# \u041B\u0418\u0420-16
    set lir1 [initLir lir1]
    set lir2 [initLir lir2]

    # \u041D\u0430\u0441\u0442\u0440\u0430\u0438\u0432\u0430\u0435\u043C \u0422\u0420\u041C-201 \u0434\u043B\u044F \u0438\u0437\u043C\u0435\u0440\u0435\u043D\u0438\u044F \u0442\u0435\u043C\u043F\u0435\u0440\u0430\u0442\u0443\u0440\u044B
    set trm [::hardware::owen::trm201::modbus::init \
		-com [measure::config::get -required rs485.serialPort] \
		-addr [measure::config::get -required trm1.addr] \
		-baud [measure::config::get trm1.baud 9600] \
	]
}

# \u0417\u0430\u0432\u0435\u0440\u0448\u0430\u0435\u043C \u0440\u0430\u0431\u043E\u0442\u0443 \u0443\u0441\u0442\u0430\u043D\u043E\u0432\u043A\u0438, \u043C\u0430\u0442\u0447\u0430\u0441\u0442\u044C \u0432 \u0438\u0441\u0445\u043E\u0434\u043D\u043E\u0435.
proc finish {} {
    global lir1 lir2 trm log

    if { [info exists lir1] } {
        # \u041F\u0435\u0440\u0435\u0432\u043E\u0434\u0438\u043C \u041B\u0418\u0420-916 \u2116 1 \u0432 \u0438\u0441\u0445\u043E\u0434\u043D\u043E\u0435 \u0441\u043E\u0441\u0442\u043E\u044F\u043D\u0438\u0435
    	::hardware::skbis::lir916::done $lir1
		unset lir1
	}

    if { [info exists lir2] } {
        # \u041F\u0435\u0440\u0435\u0432\u043E\u0434\u0438\u043C \u041B\u0418\u0420-916 \u2116 2 \u0432 \u0438\u0441\u0445\u043E\u0434\u043D\u043E\u0435 \u0441\u043E\u0441\u0442\u043E\u044F\u043D\u0438\u0435
    	::hardware::skbis::lir916::done $lir2
		unset lir2
	}

    if { [info exists trm] } {
        # \u041F\u0435\u0440\u0435\u0432\u043E\u0434\u0438\u043C \u0422\u0420\u041C-201 \u0432 \u0438\u0441\u0445\u043E\u0434\u043D\u043E\u0435 \u0441\u043E\u0441\u0442\u043E\u044F\u043D\u0438\u0435
        ::hardware::owen::trm201::modbus::done $trm
        unset trm
    }
}

proc rad2grad { v } {
	return [expr $v * 57.2957795130823]
}

proc display { phi1 phi1Err phi2 phi2Err temp tempErr tempDer { write 0 } } {
	global settings ssa::isMeasurement

	# calc gamma
	lassign [calcGamma $phi1 $phi1Err $phi2 $phi2Err] gamma gammaErr

	# calc tau
	lassign [calcTau $phi2 $phi2Err] tau tauErr

	if { $write } {
		writeDataPoint $settings(result.fileName) $temp $tempErr $tempDer $phi1 $phi1Err $phi2 $phi2Err $gamma $gammaErr $tau $tauErr 0
	}

	# convert angles to degrees
	set phi1 [rad2grad $phi1]
	set phi1Err [rad2grad $phi1Err]
	set phi2 [rad2grad $phi2]
	set phi2Err [rad2grad $phi2Err]

	# convert tau to MPa
	set tau [expr 1.0e-6 * $tau]
	set tauErr [expr 1.0e-6 * $tauErr]

	if { $ssa::isMeasurement } {
		trackEvents $phi1 $phi2 $gamma $tau $temp
	}

	if { [measure::interop::isAlone] } {
	    # \u0412\u044B\u0432\u043E\u0434\u0438\u043C \u0440\u0435\u0437\u0443\u043B\u044C\u0442\u0430\u0442\u044B \u0432 \u043A\u043E\u043D\u0441\u043E\u043B\u044C
		set phi1v [::measure::format::valueWithErr -noScale -- $phi1 $phi1Err "\u00B0"]
		set phi2v [::measure::format::valueWithErr -noScale -- $phi2 $phi2Err "\u00B0"]
		set gammav [::measure::format::valueWithErr -noScale -- $gamma $gammaErr "%%"]
		set tauv [::measure::format::valueWithErr -noScale -- $tau $tauErr "\u041C\u041F\u0430"]
    	set tv [::measure::format::valueWithErr $temp $tempErr K]
    	puts "\u03C61=$phi1v\t\u03C62=$phi2v\t\u03B3=$gammav\t\u03C4=$tauv\tT=$tv"
	} else {
	    # \u0412\u044B\u0432\u043E\u0434\u0438\u043C \u0440\u0435\u0437\u0443\u043B\u044C\u0442\u0430\u0442\u044B \u0432 \u043E\u043A\u043D\u043E \u043F\u0440\u043E\u0433\u0440\u0430\u043C\u043C\u044B
      	measure::interop::cmd [list display $phi1 $phi1Err $phi2 $phi2Err $temp $tempErr $tempDer $gamma $gammaErr $tau $tauErr $write]
	}
}

set tempValues [list]
set timeValues [list]
set startTime [clock milliseconds]

# \u0418\u0437\u043C\u0435\u0440\u044F\u0435\u043C \u0442\u0435\u043C\u043F\u0435\u0440\u0430\u0442\u0443\u0440\u0443 \u0438 \u0432\u043E\u0437\u0432\u0440\u0430\u0449\u0430\u0435\u043C \u0432\u043C\u0435\u0441\u0442\u0435 \u0441 \u0438\u043D\u0441\u0442\u0440\u0443\u043C\u0435\u043D\u0442\u0430\u043B\u044C\u043D\u043E\u0439 \u043F\u043E\u0433\u0440\u0435\u0448\u043D\u043E\u0441\u0442\u044C\u044E \u0438 \u043F\u0440\u043E\u0438\u0437\u0432\u043E\u0434\u043D\u043E\u0439
proc readTemp {} {
    global tempValues timeValues startTime DERIVATIVE_READINGS settings
    
    lassign [readTempTrm] t tErr

	if { $settings(tc.correction) != "" } {
		set t [measure::expr::eval $settings(tc.correction) $t]
	}

    # \u043D\u0430\u043A\u0430\u043F\u043B\u0438\u0432\u0430\u0435\u043C \u0437\u043D\u0430\u0447\u0435\u043D\u0438\u044F \u0432 \u043E\u0447\u0435\u0440\u0435\u0434\u0438 \u0434\u043B\u044F \u0432\u044B\u0447\u0438\u0441\u043B\u0435\u043D\u0438\u044F \u043F\u0440\u043E\u0438\u0437\u0432\u043E\u0434\u043D\u043E\u0439 
    measure::listutils::lappend tempValues $t $DERIVATIVE_READINGS
    measure::listutils::lappend timeValues [expr [clock milliseconds] - $startTime] $DERIVATIVE_READINGS
    if { [llength $tempValues] < $DERIVATIVE_READINGS } {
        set der 0.0
    } else {
        set der [expr 60000.0 * [measure::math::slope $timeValues $tempValues]] 
    }
            
    return [list $t $tErr $der]
}

# \u0421\u043D\u0438\u043C\u0430\u0435\u043C \u043F\u043E\u043A\u0430\u0437\u0430\u043D\u0438\u044F \u0432\u043E\u043B\u044C\u0442\u043C\u0435\u0442\u0440\u0430 \u043D\u0430 \u0442\u0435\u0440\u043C\u043E\u043F\u0430\u0440\u0435 \u0438 \u0432\u043E\u0437\u0432\u0440\u0430\u0449\u0430\u0435\u043C \u0442\u0435\u043C\u043F\u0435\u0440\u0430\u0442\u0443\u0440\u0443 
# \u0432\u043C\u0435\u0441\u0442\u0435 \u0441 \u0438\u043D\u0441\u0442\u0440\u0443\u043C\u0435\u043D\u0442\u0430\u043B\u044C\u043D\u043E\u0439 \u043F\u043E\u0433\u0440\u0435\u0448\u043D\u043E\u0441\u0442\u044C\u044E
proc readTempTrm {} {
#!!!
	return [list [expr 0.1 * ([clock seconds] % 10000)] 0.1]
#!!!
    global trm
    return [::hardware::owen::trm201::modbus::readTemperature $trm]
}

proc readAngles {} {
    global lir1 lir2

	lassign [::hardware::skbis::lir916::readAngle $lir1] phi1 phi1Err
	lassign [::hardware::skbis::lir916::readAngle $lir2] phi2 phi2Err

	return [list $phi1 $phi1Err $phi2 $phi2Err]
}

# \u0437\u0430\u043F\u0438\u0441\u044B\u0432\u0430\u0435\u0442 \u0442\u043E\u0447\u043A\u0443 \u0432 \u0444\u0430\u0439\u043B \u0434\u0430\u043D\u043D\u044B\u0445 \u0441 \u043F\u043E\u043F\u0443\u0442\u043D\u044B\u043C \u0432\u044B\u0447\u0438\u0441\u043B\u0435\u043D\u0438\u0435\u043C \u0443\u0434\u0435\u043B\u044C\u043D\u043E\u0433\u043E \u0441\u043E\u043F\u0440\u043E\u0442\u0438\u0432\u043B\u0435\u043D\u0438\u044F
proc writeDataPoint { fn temp tempErr tempDer phi1 phi1Err phi2 phi2Err gamma gammaErr tau tauErr manual } {
	if { $manual } {
	   set manual true
    } else {
        set manual ""
    }
    
	measure::datafile::write $fn [list \
        [measure::datafile::makeDateTime] \
		[format %0.3f $temp] [format %0.3f $tempErr] [format %0.3f $tempDer]  \
        [format %0.6g $phi1] [format %0.2g $phi1Err]    \
        [format %0.6g $phi2] [format %0.2g $phi2Err]    \
        [format %0.6g $gamma] [format %0.2g $gammaErr]    \
        [format %0.6g $tau] [format %0.2g $tauErr]    \
        $manual	\
	]
}

proc prepareEvents {} {
	global settings ssa::MAX_EVENTS ssa::EVENT_VAR ssa::EVENT_RELATION_EXPR ssa::EVENT_SOUND

	set result ""

	for { set i 0 } { $i < $ssa::MAX_EVENTS } { incr i } {
		set var "event.${i}"

		if { ![info exists settings(${var}.enabled)] || !$settings(${var}.enabled) } {
			# event is not enabled
			continue
		}

		if { ![info exists settings(${var}.what)] || ![info exists settings(${var}.relation)] || ![info exists settings(${var}.value)] || ![info exists settings(${var}.sound)]} {
			# event is not fully specified
			continue
		}

		set what $settings(${var}.what)
		if { $what < 0 || $what >= [llength $ssa::EVENT_VAR] } {
			# <what> is invalid
			continue
		}
		set what [lindex $ssa::EVENT_VAR $what]

		set relation $settings(${var}.relation)
		if { $relation < 0 || $relation >= [llength $ssa::EVENT_RELATION_EXPR] } {
			# <relation> is invalid
			continue
		}
		set relation [lindex $ssa::EVENT_RELATION_EXPR $relation]

		set value $settings(${var}.value)
		if { ![string is double $value] } {
			# <value> is invalid
			continue
		}

		set sound $settings(${var}.sound)
		if { $sound < 0 || $sound >= [llength $ssa::EVENT_SOUND] } {
			# <sound> is invalid
			continue
		}
		set sound [lindex $ssa::EVENT_SOUND $sound]

		append result "if {(\$$what $relation $value) && \[info exists prevValues($what)\] && !(\$prevValues($what) $relation $value)} {set sound \"$sound\"}\nset prevValues($what) \$$what\n"
	}

	return $result
}

proc play_sound { sound } {
	package require twapi
	twapi::play_sound $sound -alias -async
}

# track events depending on variable values
proc trackEvents { phi1 phi2 gamma tau temp } {
	global _prepared_events_ prevValues

	if { ![info exists _prepared_events_] } {
		set _prepared_events_ [prepareEvents]
	}

	set sound ""
	eval $_prepared_events_
	if { $sound != "" } {
		catch { play_sound $sound }
	}
}

proc ssa::sound-labels {} {
	package require registry
#	package require twapi_base 4.1
#	package require twapi_resource 4.1
#	package require twapi_nls 4.1
	global ssa::EVENT_SOUND log

#	set langid [twapi::get_system_default_langid]

	set result {}
	foreach s $ssa::EVENT_SOUND {
		set key "HKEY_CURRENT_USER\\AppEvents\\EventLabels\\$s"
#		set resourceName [registry get $key DispFileName]
		set label [registry get $key {}]
		lappend result $label
	}

	return $result
}

