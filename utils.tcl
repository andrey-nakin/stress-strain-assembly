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
set ssa::EVENT_SOUND { Asterisk Exclamation Exit Hand Question Start }

# max number of events
set ssa::MAX_EVENTS 10

# true when thread is working in measurement mode
set ssa::isMeasurement 0

###############################################################################
# Package-private constants & variables
###############################################################################

# Число измерений, по которым определяется производная dT/dt
set DERIVATIVE_READINGS 10

# Prev variable values
array set prevValues {}

###############################################################################
# Utility procedures
###############################################################################

# Процедура проверяет правильность настроек, при необходимости вносит поправки
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

# Инициализация приборов
proc setup {} {
    global lir1 lir2 trm

	# ЛИР-16
    set lir1 [initLir lir1]
    set lir2 [initLir lir2]

    # Настраиваем ТРМ-201 для измерения температуры
    set trm [::hardware::owen::trm201::modbus::init \
		-com [measure::config::get -required rs485.serialPort] \
		-addr [measure::config::get -required trm1.addr] \
		-baud [measure::config::get trm1.baud 9600] \
	]
}

# Завершаем работу установки, матчасть в исходное.
proc finish {} {
    global lir1 lir2 trm log

    if { [info exists lir1] } {
        # Переводим ЛИР-916 № 1 в исходное состояние
    	::hardware::skbis::lir916::done $lir1
		unset lir1
	}

    if { [info exists lir2] } {
        # Переводим ЛИР-916 № 2 в исходное состояние
    	::hardware::skbis::lir916::done $lir2
		unset lir2
	}

    if { [info exists trm] } {
        # Переводим ТРМ-201 в исходное состояние
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

#!!!	if { $ssa::isMeasurement } {
		trackEvents $phi1 $phi2 $gamma $tau $temp
#	}

	if { [measure::interop::isAlone] } {
	    # Выводим результаты в консоль
		set phi1v [::measure::format::valueWithErr -noScale -- $phi1 $phi1Err "°"]
		set phi2v [::measure::format::valueWithErr -noScale -- $phi2 $phi2Err "°"]
		set gammav [::measure::format::valueWithErr -noScale -- $gamma $gammaErr "%%"]
		set tauv [::measure::format::valueWithErr -noScale -- $tau $tauErr "МПа"]
    	set tv [::measure::format::valueWithErr $temp $tempErr K]
    	puts "φ1=$phi1v\tφ2=$phi2v\tγ=$gammav\tτ=$tauv\tT=$tv"
	} else {
	    # Выводим результаты в окно программы
      	measure::interop::cmd [list display $phi1 $phi1Err $phi2 $phi2Err $temp $tempErr $tempDer $gamma $gammaErr $tau $tauErr $write]
	}
}

set tempValues [list]
set timeValues [list]
set startTime [clock milliseconds]

# Измеряем температуру и возвращаем вместе с инструментальной погрешностью и производной
proc readTemp {} {
    global tempValues timeValues startTime DERIVATIVE_READINGS settings
    
    lassign [readTempTrm] t tErr

	if { $settings(tc.correction) != "" } {
		set t [measure::expr::eval $settings(tc.correction) $t]
	}

    # накапливаем значения в очереди для вычисления производной 
    measure::listutils::lappend tempValues $t $DERIVATIVE_READINGS
    measure::listutils::lappend timeValues [expr [clock milliseconds] - $startTime] $DERIVATIVE_READINGS
    if { [llength $tempValues] < $DERIVATIVE_READINGS } {
        set der 0.0
    } else {
        set der [expr 60000.0 * [measure::math::slope $timeValues $tempValues]] 
    }
            
    return [list $t $tErr $der]
}

# Снимаем показания вольтметра на термопаре и возвращаем температуру 
# вместе с инструментальной погрешностью
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

# записывает точку в файл данных с попутным вычислением удельного сопротивления
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
	global settings ssa::MAX_EVENTS ssa::EVENT_VAR ssa::EVENT_RELATION_EXPR

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

		append result "if {(\$$what $relation $value) && (!\[info exists prevValues($what)\] || !(\$prevValues($what) $relation $value))} {set sound \"$settings(${var}.sound)\"}\nset prevValues($what) \$$what\n"
	}

	return $result
}

proc play_sound { sound } {
	package require twapi
	twapi::play_sound "System${sound}" -alias -async
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

