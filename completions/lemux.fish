# fish completion for lemux

function __lemux_apps
    set -l data $HOME/.local/share
    set -q XDG_DATA_HOME; and set data $XDG_DATA_HOME
    for d in $data/lemux/apps/*/
        basename $d
    end
end

set -l commands status check analyze history clean purge installers remove app update optimize
set -l app_commands install update list rollback remove

complete -c lemux -f
complete -c lemux -s y -l yes -d 'Answer yes to confirmations'
complete -c lemux -l no-color -d 'Plain output'
complete -c lemux -s h -l help -d 'Show help'
complete -c lemux -s V -l version -d 'Show the version'

complete -c lemux -n "not __fish_seen_subcommand_from $commands" -a status -d 'Live dashboard with a health score'
complete -c lemux -n "not __fish_seen_subcommand_from $commands" -a analyze -d 'Where the disk space went'
complete -c lemux -n "not __fish_seen_subcommand_from $commands" -a history -d 'What lemux changed'
complete -c lemux -n "not __fish_seen_subcommand_from $commands" -a purge -d 'Delete build artifacts of your projects'
complete -c lemux -n "not __fish_seen_subcommand_from $commands" -a installers -d 'Remove installer files'
complete -c lemux -n "not __fish_seen_subcommand_from $commands" -a optimize -d 'Refresh caches and services'
complete -c lemux -n "not __fish_seen_subcommand_from $commands" -a check -d 'Health report with guided fixes'
complete -c lemux -n "not __fish_seen_subcommand_from $commands" -a clean -d 'Free space from caches'
complete -c lemux -n "not __fish_seen_subcommand_from $commands" -a remove -d 'Uninstall an app completely'
complete -c lemux -n "not __fish_seen_subcommand_from $commands" -a app -d 'Manage AppImages'
complete -c lemux -n "not __fish_seen_subcommand_from $commands" -a update -d 'Update everything'

complete -c lemux -n "__fish_seen_subcommand_from check" -l fix -d 'Offer guided repairs'
complete -c lemux -n "__fish_seen_subcommand_from status" -s w -l watch -d 'Refresh continuously'
complete -c lemux -n "__fish_seen_subcommand_from analyze" -l top -d 'How many folders' -x
complete -c lemux -n "__fish_seen_subcommand_from analyze purge" -a "(__fish_complete_directories)"
complete -c lemux -n "__fish_seen_subcommand_from history" -l json -d 'Machine-readable output'
complete -c lemux -n "__fish_seen_subcommand_from purge installers optimize" -l apply -d 'Do it (default is a dry run)'
complete -c lemux -n "__fish_seen_subcommand_from purge installers" -l all -d 'Include the ones kept by default'
complete -c lemux -n "__fish_seen_subcommand_from purge" -l days -d 'What counts as recent' -x
complete -c lemux -n "__fish_seen_subcommand_from clean" -l apply -d 'Delete instead of reporting'
complete -c lemux -n "__fish_seen_subcommand_from clean" -l trash -d 'Also empty the Trash'
complete -c lemux -n "__fish_seen_subcommand_from clean" -l orphans -d 'Also remove orphaned packages'
complete -c lemux -n "__fish_seen_subcommand_from clean" -l journal -d 'Also shrink the journal'
complete -c lemux -n "__fish_seen_subcommand_from clean" -l packages -d 'Clean the native package cache'
complete -c lemux -n "__fish_seen_subcommand_from remove; and not __fish_seen_subcommand_from app" -l apply -d 'Remove instead of reporting'
complete -c lemux -n "__fish_seen_subcommand_from update; and not __fish_seen_subcommand_from app" -l apps -d 'Only the AppImages'

complete -c lemux -n "__fish_seen_subcommand_from app; and not __fish_seen_subcommand_from $app_commands" -a install -d 'Install an AppImage'
complete -c lemux -n "__fish_seen_subcommand_from app; and not __fish_seen_subcommand_from $app_commands" -a update -d 'Update AppImages'
complete -c lemux -n "__fish_seen_subcommand_from app; and not __fish_seen_subcommand_from $app_commands" -a list -d 'List installed AppImages'
complete -c lemux -n "__fish_seen_subcommand_from app; and not __fish_seen_subcommand_from $app_commands" -a rollback -d 'Return to the previous version'
complete -c lemux -n "__fish_seen_subcommand_from app; and not __fish_seen_subcommand_from $app_commands" -a remove -d 'Uninstall an AppImage'
complete -c lemux -n "__fish_seen_subcommand_from app; and __fish_seen_subcommand_from install" -F -l from -d 'GitHub owner/repo'
complete -c lemux -n "__fish_seen_subcommand_from app; and __fish_seen_subcommand_from install" -l name -d 'Application id'
complete -c lemux -n "__fish_seen_subcommand_from app; and __fish_seen_subcommand_from install" -l move -d 'Delete the downloaded file'
complete -c lemux -n "__fish_seen_subcommand_from app; and __fish_seen_subcommand_from install" -F
complete -c lemux -n "__fish_seen_subcommand_from app; and __fish_seen_subcommand_from update rollback remove" -a "(__lemux_apps)"
complete -c lemux -n "__fish_seen_subcommand_from app; and __fish_seen_subcommand_from update" -l force -d 'Reinstall or downgrade'
complete -c lemux -n "__fish_seen_subcommand_from app; and __fish_seen_subcommand_from update" -l from -d 'GitHub owner/repo'
complete -c lemux -n "__fish_seen_subcommand_from app; and __fish_seen_subcommand_from remove" -l purge -d 'Also delete its settings'
