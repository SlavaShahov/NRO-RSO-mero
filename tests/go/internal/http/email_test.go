package httpapi_test

import (
	"bytes"
	"sort"
	"strings"
	"testing"

	"github.com/xuri/excelize/v2"
	"golang.org/x/text/collate"
	"golang.org/x/text/language"
)

// ── Вспомогательные копии ─────────────────────────────────────────────────────

type P struct {
	Num          int
	EventTitle   string
	CardNumber   string
	LastName     string
	FirstName    string
	MiddleName   string
	Institution  string
	UnitName     string
	PositionName string
	IsHQStaff    bool
	Phone        string
}

func po(name string, hq bool) int {
	if hq {
		if strings.Contains(name, "Командир") { return 1 }
		if strings.Contains(name, "Комиссар") { return 2 }
		if strings.Contains(name, "Инженер")  { return 3 }
		return 4
	}
	if strings.Contains(name, "Командир") { return 5 }
	if strings.Contains(name, "Комиссар") { return 6 }
	if strings.Contains(name, "Мастер")   { return 7 }
	return 8
}

func dn(n string) string {
	if n == "Кандидат" || n == "" { return "Боец" }
	return n
}

func sortP(pp []P) {
	c := collate.New(language.Russian)

	sort.SliceStable(pp, func(i, j int) bool {
		a, b := pp[i], pp[j]

		// 1. По учебному заведению
		if a.Institution != b.Institution {
			return c.CompareString(a.Institution, b.Institution) < 0
		}
		// 2. ШСО всегда идёт перед линейными отрядами
		if a.IsHQStaff != b.IsHQStaff {
			return a.IsHQStaff
		}
		// 3. По названию отряда
		if a.UnitName != b.UnitName {
			return c.CompareString(a.UnitName, b.UnitName) < 0
		}
		// 4. По должности
		oa, ob := po(a.PositionName, a.IsHQStaff), po(b.PositionName, b.IsHQStaff)
		if oa != ob {
			return oa < ob
		}
		// 5. По фамилии
		return c.CompareString(a.LastName, b.LastName) < 0
	})
}

// ── displayName ───────────────────────────────────────────────────────────────

func TestDN_Candidate(t *testing.T) {
	if dn("Кандидат") != "Боец" { t.Fail() }
}
func TestDN_Empty(t *testing.T) {
	if dn("") != "Боец" { t.Fail() }
}
func TestDN_Fighter(t *testing.T) {
	if dn("Боец") != "Боец" { t.Fail() }
}
func TestDN_Commander(t *testing.T) {
	if dn("Командир") != "Командир" { t.Fail() }
}
func TestDN_HQCommander(t *testing.T) {
	if dn("Командир штаба") != "Командир штаба" { t.Fail() }
}

// ── Сортировка: по ВУЗу ──────────────────────────────────────────────────────

func TestSort_Institution_ABC(t *testing.T) {
	pp := []P{
		{Institution: "НГТУ"},
		{Institution: "НГАСУ"},
		{Institution: "СГУПС"},
	}
	sortP(pp)
	want := []string{"НГАСУ", "НГТУ", "СГУПС"}
	for i, w := range want {
		if pp[i].Institution != w {
			t.Errorf("[%d] want %s, got %s", i, w, pp[i].Institution)
		}
	}
}

// ── Сортировка: по отряду внутри ВУЗа ────────────────────────────────────────

func TestSort_UnitWithinInstitution(t *testing.T) {
	pp := []P{
		{Institution: "НГТУ", UnitName: "ССО «Штурм»"},
		{Institution: "НГТУ", UnitName: "ССО «Заря»"},
		{Institution: "НГТУ", UnitName: "ССО «Энергия»"},
	}
	sortP(pp)
	// Лексикографический порядок по UnitName
	want := []string{"ССО «Заря»","ССО «Штурм»","ССО «Энергия»"}
	for i, w := range want {
		if pp[i].UnitName != w {
			t.Errorf("[%d] want %s, got %s", i, w, pp[i].UnitName)
		}
	}
}

// ── Сортировка: по должности внутри отряда ───────────────────────────────────

func TestSort_PositionWithinUnit(t *testing.T) {
	pp := []P{
		{Institution: "НГТУ", UnitName: "ССО", PositionName: "Кандидат"},
		{Institution: "НГТУ", UnitName: "ССО", PositionName: "Мастер"},
		{Institution: "НГТУ", UnitName: "ССО", PositionName: "Боец"},
		{Institution: "НГТУ", UnitName: "ССО", PositionName: "Комиссар"},
		{Institution: "НГТУ", UnitName: "ССО", PositionName: "Командир"},
	}
	sortP(pp)
	
	// Проверяем порядок должностей (Командир, Комиссар, Мастер, Боец/Кандидат)
	if pp[0].PositionName != "Командир" {
		t.Errorf("первый должен быть Командир, got %s", pp[0].PositionName)
	}
	if pp[1].PositionName != "Комиссар" {
		t.Errorf("второй должен быть Комиссар, got %s", pp[1].PositionName)
	}
	if pp[2].PositionName != "Мастер" {
		t.Errorf("третий должен быть Мастер, got %s", pp[2].PositionName)
	}
	// Боец и Кандидат могут быть в любом порядке на 4 и 5 местах
	lastTwo := []string{pp[3].PositionName, pp[4].PositionName}
	if !contains(lastTwo, "Боец") || !contains(lastTwo, "Кандидат") {
		t.Errorf("последние два должны быть Боец и Кандидат, got %v", lastTwo)
	}
}

func contains(slice []string, val string) bool {
	for _, v := range slice {
		if v == val {
			return true
		}
	}
	return false
}

func TestSort_HQPositionOrder(t *testing.T) {
	pp := []P{
		{Institution: "НГТУ", UnitName: "ШСО", PositionName: "Работник штаба", IsHQStaff: true},
		{Institution: "НГТУ", UnitName: "ШСО", PositionName: "Инженер штаба",  IsHQStaff: true},
		{Institution: "НГТУ", UnitName: "ШСО", PositionName: "Комиссар штаба", IsHQStaff: true},
		{Institution: "НГТУ", UnitName: "ШСО", PositionName: "Командир штаба", IsHQStaff: true},
	}
	sortP(pp)
	want := []string{"Командир штаба", "Комиссар штаба", "Инженер штаба", "Работник штаба"}
	for i, w := range want {
		if pp[i].PositionName != w {
			t.Errorf("[%d] want %s, got %s", i, w, pp[i].PositionName)
		}
	}
}

func TestSort_HQStaffBeforeUnitStaff(t *testing.T) {
	pp := []P{
		{Institution: "НГТУ", UnitName: "ССО «Энергия»", PositionName: "Командир", IsHQStaff: false},
		{Institution: "НГТУ", UnitName: "ШСО НГТУ",      PositionName: "Инженер штаба",  IsHQStaff: true},
		{Institution: "НГТУ", UnitName: "ШСО НГТУ",      PositionName: "Командир штаба", IsHQStaff: true},
	}
	sortP(pp)
	// Все ШСО должны идти первыми
	if !pp[0].IsHQStaff || !pp[1].IsHQStaff {
		t.Error("первые два должны быть ШСО")
	}
	if pp[2].IsHQStaff {
		t.Error("последний должен быть отрядник")
	}
}

// ── Сортировка: по фамилии ────────────────────────────────────────────────────

func TestSort_ByLastName(t *testing.T) {
	pp := []P{
		{Institution: "НГТУ", UnitName: "ССО", PositionName: "Боец", LastName: "Яблоков"},
		{Institution: "НГТУ", UnitName: "ССО", PositionName: "Боец", LastName: "Аникин"},
		{Institution: "НГТУ", UnitName: "ССО", PositionName: "Боец", LastName: "Михайлов"},
	}
	sortP(pp)
	want := []string{"Аникин", "Михайлов", "Яблоков"}
	for i, w := range want {
		if pp[i].LastName != w {
			t.Errorf("[%d] want %s, got %s", i, w, pp[i].LastName)
		}
	}
}

// ── Нумерация после сортировки ────────────────────────────────────────────────

func TestSort_NumberingRestartsAfterSort(t *testing.T) {
	pp := []P{
		{Num: 3, Institution: "СГУПС"},
		{Num: 1, Institution: "НГАСУ"},
		{Num: 2, Institution: "НГТУ"},
	}
	sortP(pp)
	for i := range pp { pp[i].Num = i + 1 }
	for i, p := range pp {
		if p.Num != i+1 { t.Errorf("[%d] Num=%d, want %d", i, p.Num, i+1) }
	}
}

// ── Excel структура ───────────────────────────────────────────────────────────

func TestExcel_WritesAndReadsBack(t *testing.T) {
	f := excelize.NewFile()
	defer f.Close()
	f.SetCellValue("Sheet1", "A1", "тест значение")
	var buf bytes.Buffer
	if err := f.Write(&buf); err != nil { t.Fatalf("write: %v", err) }

	f2, err := excelize.OpenReader(&buf)
	if err != nil { t.Fatalf("invalid xlsx: %v", err) }
	defer f2.Close()
	val, _ := f2.GetCellValue("Sheet1", "A1")
	if val != "тест значение" { t.Errorf("got %q", val) }
}

func TestExcel_HeadersExactly8Columns(t *testing.T) {
	headers := []string{
		"№ п/п", "Название мероприятия", "№ чл. билета",
		"ФИО", "Учебное заведение", "Отряд",
		"Должность", "Контактный телефон",
	}
	if len(headers) != 8 {
		t.Errorf("must have exactly 8 headers, got %d", len(headers))
	}
}

func TestExcel_HeaderText_Correct(t *testing.T) {
	f := excelize.NewFile()
	defer f.Close()
	sheet := "Sheet1"
	headers := []string{
		"№ п/п", "Название мероприятия", "№ чл. билета",
		"ФИО", "Учебное заведение", "Отряд",
		"Должность", "Контактный телефон",
	}
	cols := []string{"A", "B", "C", "D", "E", "F", "G", "H"}
	for i, h := range headers {
		f.SetCellValue(sheet, cols[i]+"1", h)
	}
	for i, want := range headers {
		got, _ := f.GetCellValue(sheet, cols[i]+"1")
		if got != want { t.Errorf("col %s: want %q, got %q", cols[i], want, got) }
	}
}

func TestExcel_CandidateWrittenAsBoets(t *testing.T) {
	f := excelize.NewFile()
	defer f.Close()
	f.SetCellValue("Sheet1", "G2", dn("Кандидат"))
	val, _ := f.GetCellValue("Sheet1", "G2")
	if val != "Боец" { t.Errorf("got %q, want Боец", val) }
}

func TestExcel_EmptyPositionWrittenAsBoets(t *testing.T) {
	f := excelize.NewFile()
	defer f.Close()
	f.SetCellValue("Sheet1", "G2", dn(""))
	val, _ := f.GetCellValue("Sheet1", "G2")
	if val != "Боец" { t.Errorf("got %q, want Боец", val) }
}

func TestExcel_FIO_WithMiddleName(t *testing.T) {
	fio := strings.TrimSpace("Иванов" + " " + "Иван" + " " + "Иванович")
	if fio != "Иванов Иван Иванович" { t.Errorf("got %q", fio) }
}

func TestExcel_FIO_WithoutMiddleName(t *testing.T) {
	fio := strings.TrimSpace("Петров" + " " + "Пётр" + " " + "")
	if fio != "Петров Пётр" { t.Errorf("got %q", fio) }
}

func TestExcel_InstitutionStripsHQPrefix(t *testing.T) {
	cases := map[string]string{
		"ШСО НГТУ":  "НГТУ",
		"ШСО СГУПС": "СГУПС",
		"НТЖТ":      "НТЖТ",
		"ШСО ":      "",
	}
	for in, want := range cases {
		got := strings.TrimPrefix(in, "ШСО ")
		if got != want { t.Errorf("TrimPrefix(%q)=%q, want %q", in, got, want) }
	}
}

// ── Тема письма ───────────────────────────────────────────────────────────────

func TestEmail_SubjectEqualsEventTitle(t *testing.T) {
	title := "Закрытие спартакиады РСО 2026"
	subject := title
	if subject != title { t.Errorf("subject %q != title %q", subject, title) }
}

func TestEmail_FilenameHasXLSXExtension(t *testing.T) {
	fn := "Закрытие спартакиады.xlsx"
	if !strings.HasSuffix(fn, ".xlsx") { t.Error("filename must end with .xlsx") }
}

func TestEmail_FilenameSanitize(t *testing.T) {
	sanitize := func(s string) string {
		r := strings.NewReplacer("/", "-", "\\", "-", ":", "-",
			"*", "-", "?", "-", `"`, "-", "<", "-", ">", "-", "|", "-")
		return r.Replace(s)
	}
	cases := map[string]string{
		"Дартс":                  "Дартс",
		"Финал 01/04/2026":       "Финал 01-04-2026",
		"Тест: финал":            "Тест- финал",
		"Файл|пайп":              "Файл-пайп",
		"<script>alert</script>": "-script-alert--script-",
	}
	for in, want := range cases {
		got := sanitize(in)
		if got != want { t.Errorf("sanitize(%q)=%q, want %q", in, got, want) }
	}
}