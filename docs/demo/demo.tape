Require uv

Set Shell "zsh"
Set Width 1920
Set Height 1080
Set FontSize 24
Set Padding 40
Set Theme "Catppuccin Mocha"
Set TypingSpeed 45ms
Set Framerate 24

Hide
Type "cd dbt && PROMPT='$ ' && RPROMPT='' && clear"
Enter
Sleep 1s
Show

Sleep 1s
Type "cat seeds/rejestr_testow.csv"
Sleep 500ms
Enter
Sleep 4s

Type "uv run dbt build --target sandbox --profiles-dir ."
Sleep 500ms
Enter
Sleep 90s
Sleep 4s
