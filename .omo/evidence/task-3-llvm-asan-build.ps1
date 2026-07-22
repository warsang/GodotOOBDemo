$env:Path = "C:\clang_llvm_20.1.7\bin;$env:Path"
cmd /c '"C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\Tools\VsDevCmd.bat" -arch=amd64 && cd /d "C:\Users\Someone\Documents\GODOT Bug demo\godot-4.4.1" && python -m SCons platform=windows target=editor dev_build=yes use_llvm=yes use_asan=yes -j12 2>&1'
