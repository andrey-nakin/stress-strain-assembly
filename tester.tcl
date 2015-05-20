#!/usr/bin/tclsh

###############################################################################
# Stress & strain measurement assembly
# Tester module
###############################################################################

package provide ssa::tester 1.0.1

package require measure::logger
package require measure::config
package require measure::interop
package require measure::sigma
package require measure::datafile
package require measure::measure
package require measure::format
package require ssa::utils

set DELAY 1000

###############################################################################
# Подпрограммы
###############################################################################

# Процедура производит периодический опрос приборов и выводит показания на экран
proc run {} {
    global DELAY log

	# инициализируем устройства
	setup

	# работаем в цикле пока не получен сигнал останова
    while { ![measure::interop::isTerminated] } {

        # считываем температуру
        lassign [readTemp] temp tempErr tempDer
        
        # считываем углы
		lassign [readAngles] phi1 phi1Err phi2 phi2Err

		# выводим результаты на экране
		display $phi1 $phi1Err $phi2 $phi2Err $temp $tempErr $tempDer

        after $DELAY
    }
}

###############################################################################
# Начало работы
###############################################################################

# Инициализируем протоколирование
set log [measure::logger::init tester]

# Читаем настройки программы
measure::config::read

# Проверяем правильность настроек
validateSettings

###############################################################################
# Основной цикл измерений
###############################################################################

# Эта команда будет вызваться в случае преждевременной остановки потока
measure::interop::registerFinalization { finish }

# Запускаем процедуру измерения
run

# Завершаем работу
finish

