#!/usr/bin/wish

###############################################################################
# Stress & strain measurement assembly
# Main module
###############################################################################

package provide app-stress-strain-assembly 1.0.0

package require Tcl 8.5
package require Tk 8.5
package require Ttk 8.5
package require Plotchart
package require Thread
package require inifile
package require math::statistics
package require measure::widget
package require measure::widget::images
package require measure::logger
package require measure::config
package require measure::com
package require measure::interop
package require measure::chart
package require measure::datafile
package require measure::format
package require startfile
package require measure::widget::fullscreen
package require hardware::skbis::lir916

package require ssa::utils

proc clearResults {} {
    global runtime chartTau_gamma chartT_t chartGamma_T chartTau_T

	set runtime(phi1) ""
	set runtime(phi2) ""
	set runtime(tau) ""
	set runtime(gamma) ""
	set runtime(temperature) ""

	measure::chart::${chartT_t}::clear
   	measure::chart::${chartTau_gamma}::clear
   	measure::chart::${chartGamma_T}::clear
   	measure::chart::${chartTau_T}::clear
}

proc startTester {} {
	measure::config::write

	clearResults

    measure::interop::clearTerminated

	measure::interop::startWorker { package require ssa::tester } {} {}
}

proc terminateTester {} {
	measure::interop::waitForWorkerThreads
}

proc stopMeasure {} {
	global w log workerId

	unset workerId

	startTester

	$w.nb.m.ctl.start configure -state normal
     
	$w.nb.m.ctl.stop configure -state disabled
	$w.nb.m.ctl.measure configure -state disabled
	$w.nb tab 3 -state normal
	$w.nb tab 4 -state normal
}

proc checkPrerequisites {} {
	global settings

	if { ![info exists settings(prog.method)] || $settings(prog.method) == "" } {
		error "\u041D\u0435 \u0432\u044B\u0431\u0440\u0430\u043D \u043C\u0435\u0442\u043E\u0434 \u0440\u0435\u0433\u0438\u0441\u0442\u0440\u0430\u0446\u0438\u0438"
	}

	if { ![info exists settings(measure.method)] || $settings(measure.method) == "" } {
		error "\u041D\u0435 \u0432\u044B\u0431\u0440\u0430\u043D \u043C\u0435\u0442\u043E\u0434 \u0438\u0437\u043C\u0435\u0440\u0435\u043D\u0438\u044F"
	}

	if { ![info exists settings(dut.length)] || $settings(dut.length) == "" || ![info exists settings(dut.r)] || $settings(dut.r) == "" || ![info exists settings(dut.momentum)] || $settings(dut.momentum) == "" } {
		error "\u041D\u0435 \u0432\u0432\u0435\u0434\u0435\u043D\u044B \u043F\u0430\u0440\u0430\u043C\u0435\u0442\u0440\u044B \u043E\u0431\u0440\u0430\u0437\u0446\u0430"
	}
}

proc startMeasure {} {
	global w log runtime chartTau_gamma workerId

	if { [catch { checkPrerequisites } err] } {
		tk_messageBox -icon error -title "\u041E\u0448\u0438\u0431\u043A\u0430" -message $err
		return 
	}

	$w.nb.m.ctl.start configure -state disabled
	$w.nb tab 3 -state disabled
	$w.nb tab 4 -state disabled

	terminateTester

	measure::config::write

    measure::interop::clearTerminated
    
	set workerId [measure::interop::startWorker { package require ssa::measure } { stopMeasure } ]

	$w.nb.m.ctl.stop configure -state normal
	$w.nb.m.ctl.measure configure -state normal
	
	clearResults

	measure::chart::${chartTau_gamma}::clear
}

proc terminateMeasure {} {
    global w log

	$w.nb.m.ctl.stop configure -state disabled
	$w.nb.m.ctl.measure configure -state disabled
	$w.nb tab 3 -state normal
	$w.nb tab 4 -state normal
	
	measure::interop::terminate
}

proc quit {} {
	::measure::config::write

	::measure::interop::waitForWorkerThreads

    ::measure::datafile::shutdown
     
	::measure::logger::shutdown

	exit
}

proc toggleProgControls {} {
	global w
	set p "$w.nb.ms.l.prog"
	set mode [measure::config::get prog.method 0]
	::measure::widget::setDisabled [expr $mode == 0] $p.timeStep
	::measure::widget::setDisabled [expr $mode == 1] $p.tempStep
}

proc changeMeasureMethod {} {
	set mode [measure::config::get measure.method 0]
# TODO
}

proc makeMeasurement {} {
	global workerId

	if { [info exists workerId] } {
		thread::send -async $workerId makeMeasurement
	}
}

proc testLir916Impl { lir btn } {
    global settings
	package require hardware::skbis::lir916

	terminateTester
	if { [catch {
		set res [::hardware::skbis::lir916::test -com $settings(rs485.serialPort) -addr $settings(${lir}.addr) -baud $settings(${lir}.baud)]
	} ] } {
		set res 0
	}
	startTester

	if { $res > 0 } {
		tk_messageBox -icon info -type ok -title "\u041E\u043F\u0440\u043E\u0441" -parent . -message "\u0421\u0432\u044F\u0437\u044C \u0443\u0441\u0442\u0430\u043D\u043E\u0432\u043B\u0435\u043D\u0430"
	} elseif { $res == 0} {
		tk_messageBox -icon error -type ok -title "\u041E\u043F\u0440\u043E\u0441" -parent . -message "\u041D\u0435\u0442 \u0441\u0432\u044F\u0437\u0438"
	} else {
		tk_messageBox -icon error -type ok -title "\u041E\u043F\u0440\u043E\u0441" -parent . -message "\u423\u441\u442\u440\u43E\u439\u441\u442\u432\u43E \u43D\u435 \u44F\u432\u43B\u44F\u435\u442\u441\u44F \u438\u441\u442\u43E\u447\u43D\u438\u43A\u43E\u43C \u43F\u438\u442\u430\u43D\u438\u44F Agilent E3645A \u438\u43B\u438 \u430\u43D\u430\u43B\u43E\u433\u43E\u43C"
	}
    $btn configure -state enabled
} 

proc testLir916 { lir btn } {
    $btn configure -state disabled
	after 100 [list testLir916Impl $lir $btn]
}

proc testAc4Impl { btn } {
    global settings

	terminateTester
	if { [catch {
		set res [::measure::com::test $settings(rs485.serialPort)]
	} ] } {
		set res 0
	}
	startTester

	if { $res } {
		tk_messageBox -icon info -type ok -title "\u041E\u043F\u0440\u043E\u0441" -parent . -message "\u0421\u0432\u044F\u0437\u044C \u0443\u0441\u0442\u0430\u043D\u043E\u0432\u043B\u0435\u043D\u0430"
	} else {
		tk_messageBox -icon error -type ok -title "\u041E\u043F\u0440\u043E\u0441" -parent . -message "\u041D\u0435\u0442 \u0441\u0432\u044F\u0437\u0438"
	}
    $btn configure -state enabled
}

proc testAc4 { btn } {
    $btn configure -state disabled
	after 100 [list testAc4Impl $btn]
}

proc setCoeff { coeff } {
	global settings

	set settings(lir2.coeff) $coeff
	::hardware::skbis::lir916::setCoeff $settings(lir1.addr) $coeff
	::hardware::skbis::lir916::setCoeff $settings(lir2.addr) $coeff
}

proc calibrateLir916 { lir btn } {

	proc readAngle { btn } {
		set angle ""
		if { [catch {
			set lir2 [initLir lir2]
			lassign [::hardware::skbis::lir916::readAngle $lir2 1] angle
			::hardware::skbis::lir916::done $lir2
		}]} {
			tk_messageBox -icon error -type ok -title "\u041E\u043F\u0440\u043E\u0441" -parent . -message "Нет ответа от датчика угла поворота"
			finish $btn
		}
		return $angle
	}

	proc step1 { p btn } {
		global startAngle

		set startAngle [readAngle $btn]
		if { $startAngle == "" } return;

		$p.lstep1 configure -state disabled
		$p.step1 configure -state disabled
		$p.lstep2 configure -state enabled
		$p.step2 configure -state enabled
	}

	proc step2 { p } {
		$p.lstep2 configure -state disabled
		$p.step2 configure -state disabled
		$p.lstep3 configure -state enabled
		$p.numOfRounds configure -state normal
		$p.save configure -state enabled
	}

	proc step3 { p btn } {
		global startAngle numOfRounds

		set pi 3.14159265358979323
		set endAngle [readAngle $btn]
		if { $endAngle == "" } return;

		setCoeff [format %0.8g [expr (2.0 * $pi * $numOfRounds) / abs($endAngle - $startAngle)]]

		finish $btn
	}

	proc finish { btn } {
		destroy .callir916
		startTester
		$btn configure -state enabled
	}

    $btn configure -state disabled

	terminateTester

	set w .callir916
	tk::toplevel $w
	wm title $w "\u041A\u0430\u043B\u0438\u0431\u0440\u043E\u0432\u043A\u0430 \u0443\u0433\u043B\u0430 \u043F\u043E\u0432\u043E\u0440\u043E\u0442\u0430"
	wm protocol $w WM_DELETE_WINDOW [list finish $btn]
	wm attributes $w -topmost 1

	set p [ttk::frame $w.c]
    grid [ttk::label $p.lstep1 -text "\u0428\u0430\u0433 1. \u0417\u0430\u0444\u0438\u043A\u0441\u0438\u0440\u0443\u0439\u0442\u0435 \u0432\u0430\u043B, \u043F\u0440\u0438\u0441\u043E\u0435\u0434\u0438\u043D\u0451\u043D\u043D\u044B\u0439 \u043A \u0434\u0430\u0442\u0447\u0438\u043A\u0443 \u0443\u0433\u043B\u0430 \u2116 2, \u0438 \u043D\u0430\u0436\u043C\u0438\u0442\u0435 \u043A\u043D\u043E\u043F\u043A\u0443 \u00AB\u0414\u0430\u043B\u044C\u0448\u0435\u00BB"] -row 0 -column 0 -columnspan 2 -sticky w
    grid [ttk::button $p.step1 -text "\u0414\u0430\u043B\u044C\u0448\u0435" -command [list step1 $p $btn] ] -row 1 -column 1 -sticky e

    grid [ttk::label $p.lstep2 -text "\u0428\u0430\u0433 2. \u041F\u0440\u043E\u0432\u0435\u0440\u043D\u0438\u0442\u0435 \u0432\u0430\u043B \u043D\u0430 \u043E\u043F\u0440\u0435\u0434\u0435\u043B\u0451\u043D\u043D\u043E\u0435 \u0447\u0438\u0441\u043B\u043E \u043E\u0431\u043E\u0440\u043E\u0442\u043E\u0432, \u0432\u043D\u043E\u0432\u044C \u0437\u0430\u0444\u0438\u043A\u0441\u0438\u0440\u0443\u0439\u0442\u0435 \u0438 \u043D\u0430\u0436\u043C\u0438\u0442\u0435 \u043A\u043D\u043E\u043F\u043A\u0443 \u00AB\u0414\u0430\u043B\u044C\u0448\u0435\u00BB" -state disabled] -row 2 -column 0 -columnspan 2 -sticky w
    grid [ttk::button $p.step2 -text "\u0414\u0430\u043B\u044C\u0448\u0435" -command [list step2 $p] -state disabled] -row 3 -column 1 -sticky e

    grid [ttk::label $p.lstep3 -text "\u0428\u0430\u0433 3. \u0412\u0432\u0435\u0434\u0438\u0442\u0435 \u0447\u0438\u0441\u043B\u043E \u043F\u043E\u0432\u043E\u0440\u043E\u0442\u043E\u0432 \u0438 \u043D\u0430\u0436\u043C\u0438\u0442\u0435 \u043A\u043D\u043E\u043F\u043A\u0443 \u00AB\u0421\u043E\u0445\u0440\u0430\u043D\u0438\u0442\u044C\u00BB" -state disabled] -row 4 -column 0 -columnspan 2 -sticky w

    grid [ttk::spinbox $p.numOfRounds -width 15 -textvariable numOfRounds -from 0 -to 1000 -increment 1 -validate key -validatecommand {string is double %P} -state disabled] -row 5 -column 0 -sticky e
    grid [ttk::button $p.save -text "\u0421\u043E\u0445\u0440\u0430\u043D\u0438\u0442\u044C" -command [list step3 $p $btn] -state disabled] -row 5 -column 1 -sticky e

	grid columnconfigure $p { 0 1 } -pad 5
	grid columnconfigure $p { 0 } -weight 1
	grid rowconfigure $p { 0 1 2 3 4 5 } -pad 5
	pack $p -fill both -expand 1 -padx 10 -pady 10
}

proc resetAngles {} {
    global settings

	if { [catch {
		set settings(lir1.zero) [::hardware::skbis::lir916::setZero $settings(lir1.addr)]
		set settings(lir2.zero) [::hardware::skbis::lir916::setZero $settings(lir2.addr)]
	} err] } {
		tk_messageBox -icon error -title "\u041E\u0448\u0438\u0431\u043A\u0430" -message $err
	}
}

proc display { phi1 phi1Err phi2 phi2Err temp tempErr tempDer gamma gammaErr tau tauErr write } {
    global runtime chartTau_gamma chartGamma_T chartTau_T chartT_t w lastDisplayTime

	set tm [clock milliseconds]
	if { [info exists lastDisplayTime] } {
		if { $tm - $lastDisplayTime < 500 } {
			return
		}
	}
	set lastDisplayTime $tm
    
	set runtime(phi1) [::measure::format::valueWithErr -noScale -- $phi1 $phi1Err ""]
	set runtime(phi2) [::measure::format::valueWithErr -noScale -- $phi2 $phi2Err ""]
	set runtime(gamma) [::measure::format::valueWithErr -noScale -- $gamma $gammaErr ""]
	set runtime(tau) [::measure::format::valueWithErr -noScale -mult 1.0e-6 -- $tau $tauErr ""]
	set runtime(temperature) [::measure::format::valueWithErr -- $temp $tempErr ""]

    measure::chart::${chartT_t}::addPoint $temp

	set tau [expr 1.0e-6 * $tau]
	if { $write } {
    	measure::chart::${chartTau_gamma}::addPoint $gamma $tau result
    	measure::chart::${chartGamma_T}::addPoint $temp $gamma result
    	measure::chart::${chartTau_T}::addPoint $temp $tau result
    } else {
    	measure::chart::${chartTau_gamma}::addPoint $gamma $tau test
    	measure::chart::${chartGamma_T}::addPoint $temp $gamma test
    	measure::chart::${chartTau_T}::addPoint $temp $tau test
    }
}

###############################################################################
# Entry point
###############################################################################

# start background logging in a separate thread
set log [measure::logger::init measure]
::measure::logger::server

# start background result file saving in a separate thread
::measure::datafile::startup

set w ""
wm title $w. "\u0423\u0441\u0442\u0430\u043D\u043E\u0432\u043A\u0430 \u043F\u043E \u0438\u0437\u043C\u0435\u0440\u0435\u043D\u0438\u044E \u0434\u0435\u0444\u043E\u0440\u043C\u0430\u0446\u0438\u0438 \u0438 \u043D\u0430\u043F\u0440\u044F\u0436\u0435\u043D\u0438\u044F. \u0412\u0435\u0440\u0441\u0438\u044F [package versions app-stress-strain-assembly]"

wm protocol $w. WM_DELETE_WINDOW { quit }

ttk::notebook $w.nb
pack $w.nb -fill both -expand 1 -padx 2 -pady 3
ttk::notebook::enableTraversal $w.nb

# Measurement tab
ttk::frame $w.nb.m
$w.nb add $w.nb.m -text " \u0418\u0437\u043C\u0435\u0440\u0435\u043D\u0438\u0435 "

set p [ttk::labelframe $w.nb.m.ctl -text " \u0423\u043F\u0440\u0430\u0432\u043B\u0435\u043D\u0438\u0435 " -pad 10]
pack $p -fill x -side bottom -padx 10 -pady 5

grid [ttk::button $p.measure -text "\u0421\u043D\u044F\u0442\u044C \u0442\u043E\u0447\u043A\u0443" -state disabled -command makeMeasurement -image ::img::next -compound left] -row 0 -column 0 -sticky w
grid [ttk::button $p.stop -text "\u041E\u0441\u0442\u0430\u043D\u043E\u0432\u0438\u0442\u044C \u0437\u0430\u043F\u0438\u0441\u044C" -command terminateMeasure -state disabled -image ::img::stop -compound left] -row 0 -column 3 -sticky e
grid [ttk::button $p.start -text "\u041D\u0430\u0447\u0430\u0442\u044C \u0437\u0430\u043F\u0438\u0441\u044C" -command startMeasure -image ::img::start -compound left] -row 0 -column 4 -sticky e

grid columnconfigure $p { 1 3 4 } -pad 10
grid columnconfigure $p { 0 2 } -pad 50
grid columnconfigure $p { 1 } -weight 1
grid rowconfigure $p { 0 1 } -pad 5

set p [ttk::labelframe $w.nb.m.v -text " \u0420\u0435\u0437\u0443\u043B\u044C\u0442\u0430\u0442\u044B \u0438\u0437\u043C\u0435\u0440\u0435\u043D\u0438\u044F " -pad 10]
pack $p -fill x -side bottom -padx 10 -pady 5

grid [ttk::label $p.lc -text "\u03C61, \u0433\u0440\u0430\u0434:"] -row 0 -column 0 -sticky w
grid [ttk::entry $p.ec -textvariable runtime(phi1) -state readonly] -row 0 -column 1 -sticky we

grid [ttk::label $p.lv -text "\u03C62, \u0433\u0440\u0430\u0434:"] -row 0 -column 3 -sticky w
grid [ttk::entry $p.ev -textvariable runtime(phi2) -state readonly] -row 0 -column 4 -sticky we

grid [ttk::button $p.reset -text "\u041E\u0431\u043D\u0443\u043B\u0438\u0442\u044C \u0443\u0433\u043B\u044B" -command [list resetAngles] ] -row 0 -column 6 -columnspan 2 -sticky e

grid [ttk::label $p.lt -text "\u041D\u0430\u043F\u0440\u044F\u0436\u0435\u043D\u0438\u0435 \u03B3, %:"] -row 1 -column 0 -sticky w
grid [ttk::entry $p.et -textvariable runtime(gamma) -state readonly] -row 1 -column 1 -sticky we

grid [ttk::label $p.lder -text "\u0414\u0435\u0444\u043E\u0440\u043C\u0430\u0446\u0438\u044F \u03C4, \u041C\u041F\u0430:"] -row 1 -column 3 -sticky w
grid [ttk::entry $p.eder -textvariable runtime(tau) -state readonly] -row 1 -column 4 -sticky we

grid [ttk::label $p.lr -text "T, \u041A:"] -row 1 -column 6 -sticky w
grid [ttk::entry $p.er -textvariable runtime(temperature) -state readonly] -row 1 -column 7 -sticky we

grid columnconfigure $p { 0 1 3 4 5 6 7 } -pad 5
grid columnconfigure $p { 2 5 } -minsize 20
grid columnconfigure $p { 1 4 7 } -weight 1
grid rowconfigure $p { 0 1 2 3 } -pad 5

set p [ttk::labelframe $w.nb.m.c -text " \u041E\u043F\u0435\u0440\u0430\u0442\u0438\u0432\u043D\u044B\u0439 \u043A\u043E\u043D\u0442\u0440\u043E\u043B\u044C " -pad 2]
pack $p -fill both -padx 10 -pady 5 -expand 1

set chartT_t [canvas $p.t_t -width 200 -height 200]
grid $chartT_t -row 0 -column 0 -sticky news
measure::chart::movingChart -ylabel "T, \u041A" -linearTrend $chartT_t

set chartTau_gamma [canvas $p.r_T -width 200 -height 200]
grid $chartTau_gamma -row 0 -column 1 -sticky news
measure::chart::staticChart -xlabel "\u041D\u0430\u043F\u0440\u044F\u0436\u0435\u043D\u0438\u0435 \u03B3, %" -ylabel "\u03C4, \u041C\u041F\u0430" -dots 1 -lines 1 $chartTau_gamma
measure::chart::${chartTau_gamma}::series test -order 1 -maxCount 10 -color #7f7fff
measure::chart::${chartTau_gamma}::series result -order 2 -maxCount 200 -thinout -color green

set chartGamma_T [canvas $p.gamma_T -width 200 -height 200]
grid $chartGamma_T -row 1 -column 0 -sticky news
measure::chart::staticChart -xlabel "\u0422\u0435\u043C\u043F\u0435\u0440\u0430\u0442\u0443\u0440\u0430 T, \u041A" -ylabel "\u03B3, %" -dots 1 -lines 1 $chartGamma_T
measure::chart::${chartGamma_T}::series test -order 1 -maxCount 10 -color #7f7fff
measure::chart::${chartGamma_T}::series result -order 2 -maxCount 200 -thinout -color green

set chartTau_T [canvas $p.tau_T -width 200 -height 200]
grid $chartTau_T -row 1 -column 1 -sticky news
measure::chart::staticChart -xlabel "\u0422\u0435\u043C\u043F\u0435\u0440\u0430\u0442\u0443\u0440\u0430 T, \u041A" -ylabel "\u03C4, \u041C\u041F\u0430" -dots 1 -lines 1 $chartTau_T
measure::chart::${chartTau_T}::series test -order 1 -maxCount 10 -color #7f7fff
measure::chart::${chartTau_T}::series result -order 2 -maxCount 200 -thinout -color green

grid columnconfigure $p { 0 1 } -weight 1
grid rowconfigure $p { 0 1 } -weight 1

place [ttk::button $p.cb -text "\u041E\u0447\u0438\u0441\u0442\u0438\u0442\u044C" -command clearResults] -anchor ne -relx 1.0 -rely 0.0

# Measurement parameters tab
ttk::frame $w.nb.ms
$w.nb add $w.nb.ms -text " \u041F\u0430\u0440\u0430\u043C\u0435\u0442\u0440\u044B \u0438\u0437\u043C\u0435\u0440\u0435\u043D\u0438\u044F "

grid [ttk::frame $w.nb.ms.l] -column 0 -row 0 -sticky nwe
grid [ttk::frame $w.nb.ms.r] -column 1 -row 0 -sticky nwe
grid [ttk::frame $w.nb.ms.b] -column 0 -columnspan 2 -row 1 -sticky we

grid columnconfigure $w.nb.ms { 0 1 } -weight 1

set p [ttk::labelframe $w.nb.ms.l.prog -text " \u041C\u0435\u0442\u043E\u0434 \u0440\u0435\u0433\u0438\u0441\u0442\u0440\u0430\u0446\u0438\u0438 " -pad 10]

grid [ttk::label $p.ltime -text "\u0412\u0440\u0435\u043C\u0435\u043D\u043D\u0430\u044F \u0437\u0430\u0432\u0438\u0441\u0438\u043C\u043E\u0441\u0442\u044C:"] -row 0 -column 0 -sticky w
grid [ttk::radiobutton $p.time -value 0 -variable settings(prog.method) -command toggleProgControls] -row 0 -column 1 -sticky e

grid [ttk::label $p.ltimeStep -text "  \u0412\u0440\u0435\u043C\u0435\u043D\u043D\u043E\u0439 \u0448\u0430\u0433, \u043C\u0441:"] -row 1 -column 0 -sticky w
grid [ttk::spinbox $p.timeStep -width 10 -textvariable settings(prog.time.step) -from 0 -to 1000000 -increment 100 -validate key -validatecommand {string is double %P}] -row 1 -column 1 -sticky e

grid [ttk::label $p.ltemp -text "\u0422\u0435\u043C\u043F\u0435\u0440\u0430\u0442\u0443\u0440\u043D\u0430\u044F \u0437\u0430\u0432\u0438\u0441\u0438\u043C\u043E\u0441\u0442\u044C:"] -row 2 -column 0 -sticky w
grid [ttk::radiobutton $p.temp -value 1 -variable settings(prog.method) -command toggleProgControls] -row 2 -column 1 -sticky e

grid [ttk::label $p.ltempStep -text "  \u0422\u0435\u043C\u043F\u0435\u0440\u0430\u0442\u0443\u0440\u043D\u044B\u0439 \u0448\u0430\u0433, \u041A:"] -row 3 -column 0 -sticky w
grid [ttk::spinbox $p.tempStep -width 10 -textvariable settings(prog.temp.step) -from 0 -to 1000 -increment 1 -validate key -validatecommand {string is double %P}] -row 3 -column 1 -sticky e

grid [ttk::label $p.lman -text "\u0412\u0440\u0443\u0447\u043D\u0443\u044E:"] -row 4 -column 0 -sticky w
grid [ttk::radiobutton $p.man -value 2 -variable settings(prog.method) -command toggleProgControls] -row 4 -column 1 -sticky e

grid columnconfigure $p {0 1} -pad 5
grid rowconfigure $p {0 1 2 3 4} -pad 5
grid columnconfigure $p { 1 } -weight 1

pack $p -fill x -padx 10 -pady 5

set p [ttk::labelframe $w.nb.ms.r.measure -text " \u041C\u0435\u0442\u043E\u0434 \u0438\u0437\u043C\u0435\u0440\u0435\u043D\u0438\u044F " -pad 10]

grid [ttk::label $p.ltime -text "\u0414\u0438\u043D\u0430\u043C\u0438\u0447\u0435\u0441\u043A\u0438\u0439 \u043C\u043E\u043C\u0435\u043D\u0442:"] -row 0 -column 0 -sticky w
grid [ttk::radiobutton $p.dynamic -value 0 -variable settings(measure.method) -command changeMeasureMethod] -row 0 -column 1 -sticky e

grid [ttk::label $p.ltemp -text "\u041F\u043E\u0441\u0442\u043E\u044F\u043D\u043D\u044B\u0439 \u043C\u043E\u043C\u0435\u043D\u0442:"] -row 1 -column 0 -sticky w
grid [ttk::radiobutton $p.const -value 1 -variable settings(measure.method) -command changeMeasureMethod] -row 1 -column 1 -sticky e

grid columnconfigure $p {0 1} -pad 5
grid rowconfigure $p {0 1 2 3 4} -pad 5
grid columnconfigure $p { 1 } -weight 1

pack $p -fill x -padx 10 -pady 5

# DUT parameters tab
ttk::frame $w.nb.dut
$w.nb add $w.nb.dut -text " \u041E\u0431\u0440\u0430\u0437\u0435\u0446 "

set p [ttk::labelframe $w.nb.dut.dut -text " \u0413\u0435\u043E\u043C\u0435\u0442\u0440\u0438\u0447\u0435\u0441\u043A\u0438\u0435 \u043F\u0430\u0440\u0430\u043C\u0435\u0442\u0440\u044B " -pad 10]
pack $p -fill x -padx 10 -pady 5

grid [ttk::label $p.llen -text "\u0414\u043B\u0438\u043D\u0430, \u043C\u043C:"] -row 0 -column 0 -sticky w
grid [ttk::spinbox $p.len -width 10 -textvariable settings(dut.length) -from 0 -to 1000 -increment 1 -validate key -validatecommand {string is double %P}] -row 0 -column 1 -sticky e
grid [ttk::label $p.llene -text "\u00b1"] -row 0 -column 2 -sticky e
grid [ttk::spinbox $p.lene -width 10 -textvariable settings(dut.lengthErr) -from 0 -to 100 -increment 0.1 -validate key -validatecommand {string is double %P}] -row 0 -column 3 -sticky e

grid [ttk::label $p.lr -text "\u0420\u0430\u0434\u0438\u0443\u0441, \u043C\u043C:"] -row 1 -column 0 -sticky w
grid [ttk::spinbox $p.r -width 10 -textvariable settings(dut.r) -from 0 -to 1000 -increment 1 -validate key -validatecommand {string is double %P}] -row 1 -column 1 -sticky e
grid [ttk::label $p.lre -text "\u00b1"] -row 1 -column 2 -sticky e
grid [ttk::spinbox $p.re -width 10 -textvariable settings(dut.rErr) -from 0 -to 100 -increment 0.1 -validate key -validatecommand {string is double %P}] -row 1 -column 3 -sticky e

grid [ttk::label $p.lmomentum -text "\u041C\u043E\u043C\u0435\u043D\u0442, \u041D/\u043C:"] -row 2 -column 0 -sticky w
grid [ttk::spinbox $p.momentum -width 10 -textvariable settings(dut.momentum) -from 0 -to 1000 -increment 1 -validate key -validatecommand {string is double %P}] -row 2 -column 1 -sticky e
grid [ttk::label $p.lmomentume -text "\u00b1"] -row 2 -column 2 -sticky e
grid [ttk::spinbox $p.momentume -width 10 -textvariable settings(dut.momentumErr) -from 0 -to 100 -increment 0.1 -validate key -validatecommand {string is double %P}] -row 2 -column 3 -sticky e

grid columnconfigure $p { 0 1 2 3 } -pad 5
grid rowconfigure $p { 0 1 2 } -pad 5
grid columnconfigure $p { 0 } -weight 1

set p [ttk::labelframe $w.nb.dut.reg -text " \u0424\u0430\u0439\u043B\u044B " -pad 10]

grid [ttk::label $p.lname -text "\u0418\u043C\u044F \u0444\u0430\u0439\u043B\u0430 \u0440\u0435\u0437\u0443\u043B\u044C\u0442\u0430\u0442\u043E\u0432: " -anchor e] -row 0 -column 0 -sticky w
grid [ttk::entry $p.name -textvariable settings(result.fileName)] -row 0 -column 1 -columnspan 4 -sticky we

grid [ttk::label $p.lformat -text "\u0424\u043E\u0440\u043C\u0430\u0442 \u0444\u0430\u0439\u043B\u043E\u0432:"] -row 3 -column 0 -sticky w
grid [ttk::combobox $p.format -width 10 -textvariable settings(result.format) -state readonly -values [list TXT CSV]] -row 3 -column 1 -columnspan 2 -sticky w

grid [ttk::label $p.lrewrite -text "\u041F\u0435\u0440\u0435\u043F\u0438\u0441\u0430\u0442\u044C \u0444\u0430\u0439\u043B\u044B:"] -row 3 -column 3 -sticky e
grid [ttk::checkbutton $p.rewrite -variable settings(result.rewrite)] -row 3 -column 4 -sticky e

grid [ttk::label $p.lcomment -text "\u041A\u043E\u043C\u043C\u0435\u043D\u0442\u0430\u0440\u0438\u0439: " -anchor e] -row 4 -column 0 -sticky w
grid [ttk::entry $p.comment -textvariable settings(result.comment)] -row 4 -column 1  -columnspan 4 -sticky we

grid columnconfigure $p {0 1 3 4} -pad 5
grid columnconfigure $p { 2 } -weight 1
grid rowconfigure $p { 0 1 2 3 4 } -pad 5
grid rowconfigure $p { 5 } -pad 10

pack $p -fill x -padx 10 -pady 5

# Device parameters tab

ttk::frame $w.nb.tsetup
$w.nb add $w.nb.tsetup -text " \u041F\u0430\u0440\u0430\u043C\u0435\u0442\u0440\u044B \u043F\u0440\u0438\u0431\u043E\u0440\u043E\u0432 "

set p [ttk::labelframe $w.nb.tsetup.rs485 -text " \u041F\u0440\u0435\u043E\u0431\u0440\u0430\u0437\u043E\u0432\u0430\u0442\u0435\u043B\u044C \u0438\u043D\u0442\u0435\u0440\u0444\u0435\u0439\u0441\u043E\u0432 RS-485/USB \u0410\u04214" -pad 10]
pack $p -fill x -padx 10 -pady 5

grid [ttk::label $p.lrs485 -text "\u041F\u043E\u0441\u043b\u0435\u0434\u043e\u0432\u0430\u0442\u0435\u043b\u044c\u043d\u044b\u0439 \u043f\u043e\u0440\u0442:"] -row 0 -column 0 -sticky w
grid [ttk::combobox $p.rs485 -width 20 -textvariable settings(rs485.serialPort) -values [measure::com::allPorts]] -row 0 -column 1 -sticky w

grid [ttk::button $p.test -text "\u041E\u043F\u0440\u043E\u0441" -command [list testAc4 $p.test] ] -row 0 -column 2 -sticky e

grid columnconfigure $p { 0 1 2 } -pad 5
grid columnconfigure $p { 2 } -weight 1
grid rowconfigure $p { 0 1 } -pad 5

set p [ttk::labelframe $w.nb.tsetup.tcm -text " \u0418\u0437\u043C\u0435\u0440\u0438\u0442\u0435\u043B\u044C \u0442\u0435\u043C\u043F\u0435\u0440\u0430\u0442\u0443\u0440\u044B \u0422\u0420\u041C-201 " -pad 10]
pack $p -fill x -padx 10 -pady 5

grid [ttk::label $p.lnetAddr -text "\u0421\u0435\u0442\u0435\u0432\u043E\u0439 \u0430\u0434\u0440\u0435\u0441:"] -row 0 -column 0 -sticky w
grid [ttk::spinbox $p.netAddr -width 6 -textvariable settings(trm1.addr) -from 1 -to 2040 -validate key -validatecommand {string is integer %P}] -row 0 -column 1 -sticky w

grid [ttk::label $p.lbaud -text "\u0421\u043A\u043E\u0440\u043E\u0441\u0442\u044C, \u0431\u043E\u0434/\u0441:"] -row 0 -column 2 -sticky w
grid [ttk::combobox $p.baud -width 8 -textvariable settings(trm1.baud) -state readonly -values {9600 19200 28800 38400 57600 76800}] -row 0 -column 3 -sticky w

grid [ttk::label $p.lprotocol -text "\u041F\u0440\u043E\u0442\u043E\u043A\u043E\u043B \u043E\u0431\u043C\u0435\u043D\u0430:"] -row 0 -column 4 -sticky w
grid [ttk::combobox $p.protocol -width 12 -textvariable settings(trm1.protocol) -state readonly -values {OWEN Modbus-RTU}] -row 0 -column 5 -sticky w

grid [ttk::button $p.test -text "\u041E\u043F\u0440\u043E\u0441" -command [list ::measure::widget::testTrm201 settings(rs485.serialPort) settings(trm1.rs485Addr) $p.test] ] -row 0 -column 6 -sticky e

grid columnconfigure $p { 0 1 2 3 4 5 6 } -pad 5
grid columnconfigure $p { 6 } -weight 1
grid rowconfigure $p { 0 1 } -pad 5

set p [ttk::labelframe $w.nb.tsetup.lir1 -text " \u0414\u0435\u043A\u043E\u0434\u0435\u0440 \u0443\u0433\u043B\u0430 \u043F\u043E\u0432\u043E\u0440\u043E\u0442\u0430 \u041B\u0418\u0420-916 \u2116 1" -pad 10]
pack $p -fill x -padx 10 -pady 5

grid [ttk::label $p.lnetAddr -text "\u0421\u0435\u0442\u0435\u0432\u043E\u0439 \u0430\u0434\u0440\u0435\u0441:"] -row 0 -column 0 -sticky w
grid [ttk::spinbox $p.netAddr -width 6 -textvariable settings(lir1.addr) -from 1 -to 2040 -validate key -validatecommand {string is integer %P}] -row 0 -column 1 -sticky w

grid [ttk::label $p.lbaud -text "\u0421\u043A\u043E\u0440\u043E\u0441\u0442\u044C, \u0431\u043E\u0434/\u0441:"] -row 0 -column 2 -sticky w
grid [ttk::combobox $p.baud -width 8 -textvariable settings(lir1.baud) -state readonly -values {9600 19200 28800 38400 57600 76800}] -row 0 -column 3 -sticky w

grid [ttk::button $p.test -text "\u041E\u043F\u0440\u043E\u0441" -command [list testLir916 lir1 $p.test] ] -row 0 -column 6 -sticky e

grid columnconfigure $p { 0 1 2 3 4 5 6 } -pad 5
grid columnconfigure $p { 6 } -weight 1
grid rowconfigure $p { 0 1 } -pad 5

set p [ttk::labelframe $w.nb.tsetup.lir2 -text " \u0414\u0435\u043A\u043E\u0434\u0435\u0440 \u0443\u0433\u043B\u0430 \u043F\u043E\u0432\u043E\u0440\u043E\u0442\u0430 \u041B\u0418\u0420-916 \u2116 2" -pad 10]
pack $p -fill x -padx 10 -pady 5

grid [ttk::label $p.lnetAddr -text "\u0421\u0435\u0442\u0435\u0432\u043E\u0439 \u0430\u0434\u0440\u0435\u0441:"] -row 0 -column 0 -sticky w
grid [ttk::spinbox $p.netAddr -width 6 -textvariable settings(lir2.addr) -from 1 -to 2040 -validate key -validatecommand {string is integer %P}] -row 0 -column 1 -sticky w

grid [ttk::label $p.lbaud -text "\u0421\u043A\u043E\u0440\u043E\u0441\u0442\u044C, \u0431\u043E\u0434/\u0441:"] -row 0 -column 2 -sticky w
grid [ttk::combobox $p.baud -width 8 -textvariable settings(lir2.baud) -state readonly -values {9600 19200 28800 38400 57600 76800}] -row 0 -column 3 -sticky w

grid [ttk::button $p.test -text "\u041E\u043F\u0440\u043E\u0441" -command [list testLir916 lir2 $p.test] ] -row 0 -column 6 -sticky e

grid columnconfigure $p { 0 1 2 3 4 5 6 } -pad 5
grid columnconfigure $p { 6 } -weight 1
grid rowconfigure $p { 0 1 } -pad 5

# Calibration tab
ttk::frame $w.nb.cal
$w.nb add $w.nb.cal -text " \u041A\u0430\u043B\u0438\u0431\u0440\u043E\u0432\u043A\u0430 \u043F\u0440\u0438\u0431\u043E\u0440\u043E\u0432 "

set p [ttk::labelframe $w.nb.cal.lir -text " \u041B\u0418\u0420-916" -pad 10]
pack $p -fill x -padx 10 -pady 5

grid [ttk::label $p.lcoeff -text "\u041A\u043E\u044D\u0444\u0444\u0438\u0446\u0438\u0435\u043D\u0442 \u043F\u0435\u0440\u0435\u0441\u0447\u0451\u0442\u0430 \u0443\u0433\u043B\u0430 \u043F\u043E\u0432\u043E\u0440\u043E\u0442\u0430:"] -row 0 -column 0 -sticky w
grid [ttk::spinbox $p.coeff -width 12 -textvariable settings(lir2.coeff) -from 0.001 -to 1000 -validate key -validatecommand {string is double %P}] -row 0 -column 1 -sticky w

grid [ttk::button $p.test -text "\u041E\u043F\u0440\u0435\u0434\u0435\u043B\u0438\u0442\u044C \u043A\u043E\u044D\u0444\u0444\u0438\u0446\u0438\u0435\u043D\u0442" -command [list calibrateLir916 lir2 $p.test] ] -row 0 -column 6 -sticky e

grid columnconfigure $p { 0 1 2 3 4 5 6 } -pad 5
grid columnconfigure $p { 6 } -weight 1
grid rowconfigure $p { 0 1 } -pad 5

# botton panel
frame $w.fr
pack $w.fr -fill x -side bottom
pack [ttk::button $w.fr.bexit -text "\u0412\u044b\u0445\u043e\u0434" -image ::img::delete -compound left -command quit] -padx 5 -pady {20 5} -side right

pack [ttk::label $w.fr.lhint -text "F11: \u0432\u043A\u043B\u044E\u0447\u0438\u0442\u044C/\u0432\u044B\u043A\u043B\u044E\u0447\u0438\u0442\u044C \u043F\u043E\u043B\u043D\u043E\u044D\u043A\u0440\u0430\u043D\u043D\u044B\u0439 \u0440\u0435\u0436\u0438\u043C"] -padx 5 -pady {20 5} -side left

# read configuration from INI file
measure::config::read

toggleProgControls

startTester

#vwait forever
thread::wait

