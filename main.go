package main

import (
	_ "embed"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"syscall"

	"golang.org/x/sys/windows"
)

//go:embed PrintCleaner.ps1
var scriptContent []byte

func main() {
	if !amIAdmin() {
		runMeElevated()
		return
	}

	// Create a temporary file for the script
	tempDir := os.TempDir()
	tempFile := filepath.Join(tempDir, "PrintCleaner_Temp.ps1")

	err := os.WriteFile(tempFile, scriptContent, 0644)
	if err != nil {
		fmt.Printf("Error creating temp file: %v\n", err)
		fmt.Println("Press Enter to exit...")
		fmt.Scanln()
		return
	}
	defer os.Remove(tempFile)

	// Launch PowerShell with the script
	cmd := exec.Command("powershell.exe", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", tempFile)

	// Connect IO
	cmd.Stdin = os.Stdin
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr

	err = cmd.Run()
	if err != nil {
		// Only show error if it wasn't just a clean exit from the script
		// (The script manages its own UI pauses)
		fmt.Printf("Program exited: %v\n", err)
	}
}

func amIAdmin() bool {
	var sid *windows.SID

	// Although this looks huge, we are just creating the SID for the Builtin Administrators group.
	// WinBuiltinAdministratorsSid = 26
	err := windows.AllocateAndInitializeSid(
		&windows.SECURITY_NT_AUTHORITY,
		2,
		windows.SECURITY_BUILTIN_DOMAIN_RID,
		windows.DOMAIN_ALIAS_RID_ADMINS,
		0, 0, 0, 0, 0, 0,
		&sid,
	)
	if err != nil {
		return false
	}
	defer windows.FreeSid(sid)

	// This token check is the standard way to see if the current process has the admin token.
	token := windows.Token(0)
	member, err := token.IsMember(sid)
	if err != nil {
		return false
	}
	return member
}

func runMeElevated() {
	verb := "runas"
	exe, _ := os.Executable()
	cwd, _ := os.Getwd()
	args := strings.Join(os.Args[1:], " ")

	verbPtr, _ := syscall.UTF16PtrFromString(verb)
	exePtr, _ := syscall.UTF16PtrFromString(exe)
	cwdPtr, _ := syscall.UTF16PtrFromString(cwd)
	argsPtr, _ := syscall.UTF16PtrFromString(args)

	var showCmd int32 = 1 // SW_NORMAL

	// Use ShellExecute to relaunch with "runas" (Admin)
	err := windows.ShellExecute(0, verbPtr, exePtr, argsPtr, cwdPtr, showCmd)
	if err != nil {
		fmt.Println("Error requesting Administrator privileges:", err)
		fmt.Println("Press Enter to exit...")
		fmt.Scanln()
	}
	// Exit the current non-admin process
	os.Exit(0)
}