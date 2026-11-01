
package main

import (
	"bufio"
	"fmt"
	"os"
	"os/exec"
	"regexp"
	"sort"
	"strings"
	"sync"
	"time"
)

const (
	checkInterval  = 3 * time.Second
	rejoinCooldown = 30 * time.Second
)

var (
	packages   []string
	lastRejoin = make(map[string]time.Time)
	rejoinLock sync.Mutex
)

var errorPatterns = []string{
	"disconnected",
	"connection lost",
	"connection failed",
	"lost connection",
	"error code: 273",
	"error code: 277",
	"error code 273",
	"error code 277",
	"same account launched",
	"teleport failed",
	"teleportinitfailed",
	"connection timeout",
	"fatal error",
	"anr in",
	"am_anr",
}

// รันคำสั่ง Android
func run(name string, args ...string) string {
	cmd := exec.Command(name, args...)
	out, _ := cmd.CombinedOutput()
	return strings.TrimSpace(string(out))
}

// ค้นหา Roblox Package อัตโนมัติ
func getPackages() []string {
	out := run("pm", "list", "packages")

	var found []string

	for _, line := range strings.Split(out, "\n") {
		pkg := strings.TrimSpace(
			strings.TrimPrefix(line, "package:"),
		)

		if strings.HasPrefix(pkg, "com.roblox.") {
			found = append(found, pkg)
		}
	}

	sort.Strings(found)
	return found
}

// อ่านลิงก์ Rejoin
func getLink() string {
	home := os.Getenv("HOME")
	data, err := os.ReadFile(home + "/.rejoin_link")

	if err != nil {
		return ""
	}

	return strings.TrimSpace(string(data))
}

// ตรวจ PID
func getPID(pkg string) string {
	return run("pidof", pkg)
}

// ตรวจว่า Package ทำงานหรือไม่
func isRunning(pkg string) bool {
	return getPID(pkg) != ""
}

// เปิด Roblox
func openPackage(pkg string) {
	link := getLink()

	if link != "" {
		run(
			"am", "start",
			"-a", "android.intent.action.VIEW",
			"-d", link,
			"-p", pkg,
		)
		return
	}

	run("monkey", "-p", pkg, "1")
}

// รีสตาร์ท Package
func restartPackage(pkg string, reason string) {
	rejoinLock.Lock()

	now := time.Now()
	last := lastRejoin[pkg]

	if now.Sub(last) < rejoinCooldown {
		rejoinLock.Unlock()
		return
	}

	lastRejoin[pkg] = now
	rejoinLock.Unlock()

	fmt.Printf(
		"\n[REJOIN] %s | %s\n",
		pkg,
		reason,
	)

	out := run(
		"su",
		"-c",
		"am force-stop "+pkg,
	)

	if out != "" {
		fmt.Println("[STOP]", out)
	}

	time.Sleep(3 * time.Second)

	openPackage(pkg)

	fmt.Printf("[OPENED] %s\n", pkg)
}

// ตรวจข้อความ Error
func matchesError(line string) bool {
	lower := strings.ToLower(line)

	for _, keyword := range errorPatterns {
		if strings.Contains(lower, keyword) {
			return true
		}
	}

	return false
}

// หา Package จาก PID
func findPackageByPID(pid string) string {
	if pid == "" {
		return ""
	}

	for _, pkg := range packages {
		pids := strings.Fields(getPID(pkg))

		for _, p := range pids {
			if p == pid {
				return pkg
			}
		}
	}

	return ""
}

// ตรวจ Logcat
func monitorLogcat() {
	fmt.Println("[LOGCAT] Starting...")

	cmd := exec.Command(
		"logcat",
		"-v",
		"threadtime",
	)

	stdout, err := cmd.StdoutPipe()

	if err != nil {
		fmt.Println("[ERROR]", err)
		return
	}

	if err := cmd.Start(); err != nil {
		fmt.Println("[ERROR]", err)
		return
	}

	scanner := bufio.NewScanner(stdout)
	scanner.Buffer(
		make([]byte, 4096),
		1024*1024,
	)

	pidPattern := regexp.MustCompile(
		`^\S+\s+\S+\s+(\d+)\s+\d+\s+[A-Z]`,
	)

	for scanner.Scan() {
		line := scanner.Text()

		if !matchesError(line) {
			continue
		}

		fmt.Println("\n[ERROR DETECTED]", line)

		match := pidPattern.FindStringSubmatch(line)

		if len(match) < 2 {
			fmt.Println("[WARNING] ไม่พบ PID")
			continue
		}

		pkg := findPackageByPID(match[1])

		if pkg == "" {
			fmt.Println("[WARNING] ไม่พบ Package ที่ตรงกับ PID")
			continue
		}

		go restartPackage(pkg, line)
	}

	fmt.Println("[LOGCAT] Stopped")
	cmd.Process.Kill()
}

// ตรวจ Package ที่หยุดทำงาน
func monitorPackages() {
	fmt.Println("[PROCESS] Monitoring...")

	for {
		for _, pkg := range packages {
			if !isRunning(pkg) {
				go restartPackage(
					pkg,
					"PROCESS NOT RUNNING",
				)
			}
		}

		time.Sleep(checkInterval)
	}
}

// แสดง Package ทั้งหมด
func showPackages() {
	fmt.Println("\n========== ROBLOX PACKAGES ==========")

	for i, pkg := range packages {
		fmt.Printf(
			"[%d] %s | PID: %s\n",
			i+1,
			pkg,
			getPID(pkg),
		)
	}

	fmt.Println("=====================================")
}

func main() {
	fmt.Println("================================")
	fmt.Println("       ARIWAA GO REJOIN")
	fmt.Println("================================")

	packages = getPackages()

	if len(packages) == 0 {
		fmt.Println("[ERROR] ไม่พบ Roblox Package")
		return
	}

	showPackages()

	if getLink() == "" {
		fmt.Println("[WARNING] ไม่พบ ~/.rejoin_link")
		fmt.Println("[INFO] จะเปิดหน้าแอปแทน")
	}

	fmt.Println("\n[START] Monitoring Roblox...")

	go monitorPackages()

	for {
		monitorLogcat()
		time.Sleep(2 * time.Second)
	}
}
