@echo off
set https_proxy=http://127.0.0.1:7890
git add .
set /p msg="输入存档备注: "
git commit -m "%msg%"
git push
echo 完成！
pause