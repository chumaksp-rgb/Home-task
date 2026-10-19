# ==============================================================================
# Курсовий проєкт, тема 5: Метроном
#
# create_project.tcl -- відтворює проєкт Vivado з Block Design
# (MicroBlaze + axi_metronome) і налаштуванням системної симуляції.
#
# Запуск із командного рядка (Vivado 2025.2):
#   vivado -mode batch -source scripts/create_project.tcl
#   vivado -mode batch -source scripts/create_project.tcl -tclargs <папка_проєкту>
# або в Tcl-консолі Vivado:
#   source <репозиторій>/scripts/create_project.tcl
#
# За замовчуванням проєкт створюється в <репозиторій>/vivado_tcl/Metronome,
# щоб не зачепити робочий проєкт vivado/Metronome. Папку vivado_tcl/
# ігнорує git.
#
# Вихідні файли не копіюються в проєкт, а підключаються з репозиторію:
#   ip_repo/                                   -- репозиторій IP (axi_metronome)
#   scripts/Metronome_bd.tcl                   -- Block Design (згенеровано write_bd_tcl)
#   vivado/Metronome/Metronome.srcs/sim_1/new/tb_metronome_system.v -- системний тестбенч
#   vivado/Metronome/tb_metronome_system_behav.wcfg                 -- налаштування діаграм
#   vitis/app_metronome/build/app_metronome.elf -- програма для MicroBlaze (якщо вже зібрана у Vitis)
# ==============================================================================

# ---- Шляхи ----
set script_dir [file dirname [file normalize [info script]]]
set repo_dir   [file normalize [file join $script_dir ..]]

if { [info exists ::argc] && $::argc > 0 } {
    set proj_dir [file normalize [lindex $::argv 0]]
} else {
    set proj_dir [file join $repo_dir vivado_tcl Metronome]
}

set proj_name   Metronome
set part        xc7z020clg400-1
set ip_repo     [file join $repo_dir ip_repo]
set bd_script   [file join $script_dir Metronome_bd.tcl]
set tb_file     [file join $repo_dir vivado Metronome Metronome.srcs sim_1 new tb_metronome_system.v]
set wcfg_file   [file join $repo_dir vivado Metronome tb_metronome_system_behav.wcfg]
set elf_file    [file join $repo_dir vitis app_metronome build app_metronome.elf]

puts "Project directory: $proj_dir"

# ---- Проєкт ----
create_project $proj_name $proj_dir -part $part -force
set_property target_language Verilog [current_project]

# ---- Репозиторій IP з axi_metronome ----
set_property ip_repo_paths [list $ip_repo] [current_project]
update_ip_catalog

# ---- Block Design ----
# Скрипт сам створює дизайн Metronome у поточному проєкті
source $bd_script

# CLK_HZ = 1000 -- значення для симуляції (збігається зі значенням за замовчуванням,
# тому write_bd_tcl його не записує; задаємо явно)
set_property CONFIG.CLK_HZ {1000} [get_bd_cells axi_metronome_0]

validate_bd_design
save_bd_design

# ---- HDL-обгортка, верхній модуль ----
set bd_file [get_files ${proj_name}.bd]
set wrapper [make_wrapper -files $bd_file -top]
add_files -norecurse $wrapper
set_property top ${proj_name}_wrapper [get_filesets sources_1]
update_compile_order -fileset sources_1

# Вихідні файли Block Design (моделі для симуляції, файли для синтезу).
# GUI створює їх сам перед запуском, а в пакетному режимі -- ні.
generate_target all $bd_file
export_ip_user_files -of_objects $bd_file -no_script -sync -force -quiet

# ---- Системна симуляція ----
add_files -fileset sim_1 -norecurse $tb_file
set_property top tb_metronome_system [get_filesets sim_1]
set_property top_lib xil_defaultlib [get_filesets sim_1]

if { [file exists $wcfg_file] } {
    add_files -fileset sim_1 -norecurse $wcfg_file
    set_property xsim.view $wcfg_file [get_filesets sim_1]
}

# ELF прив'язується до microblaze_0 лише для симуляції (Tools -> Associate ELF Files)
if { [file exists $elf_file] } {
    add_files -fileset sim_1 -norecurse $elf_file
    set_property SCOPED_TO_REF   $proj_name    [get_files -all -of_objects [get_filesets sim_1] $elf_file]
    set_property SCOPED_TO_CELLS microblaze_0  [get_files -all -of_objects [get_filesets sim_1] $elf_file]
} else {
    puts "WARNING: $elf_file not found. Build app_metronome in Vitis, then associate the ELF with microblaze_0 (Tools -> Associate ELF Files)."
}
update_compile_order -fileset sim_1

puts "Project $proj_name created in $proj_dir"
