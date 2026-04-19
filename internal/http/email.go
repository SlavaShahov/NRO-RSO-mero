package httpapi

import (
	"bytes"
	"crypto/tls"
	"encoding/base64"
	"fmt"
	"net/smtp"
	"strings"
	"time"

	"github.com/xuri/excelize/v2"

	"rso-events/internal/config"
)

// EventParticipant — строка в списке участников мероприятия
type EventParticipant struct {
	Num          int
	EventTitle   string
	CardNumber   string
	LastName     string
	FirstName    string
	MiddleName   string
	Institution  string // учебное заведение (штаб без «ШСО »)
	UnitName     string
	PositionName string // отображаемое название должности
	PositionCode string // код для сортировки
	Phone        string
}

// positionSortOrder — порядок должностей согласно ТЗ:
// Командир ШСО → Комиссар ШСО → Инженер ШСО → Работник ШСО →
// Командир отряда → Комиссар отряда → Мастер/Инженер отряда → Боец
//
// Коды ШСО:    commander, commissioner, engineer, worker
// Коды отряда: commander, commissioner, master, fighter, candidate
//
// Чтобы различить ШСО и отряд — смотрим PositionCode из таблицы:
// hq_positions.code vs unit_positions.code
// В GetEventParticipants запрос возвращает:
//   ШСО-должность:    hp.code (commander/commissioner/engineer/worker)
//   Отряд-должность:  up.code (commander/commissioner/master/fighter/candidate)
// Они имеют пересекающиеся коды (commander/commissioner), поэтому сортируем
// по PositionName — оно уникально (Командир штаба vs Командир)
func positionSortOrder(posName string, isHQStaff bool) int {
	if isHQStaff {
		// Должности штаба — идут первыми
		switch {
		case strings.Contains(posName, "Командир"):    return 1
		case strings.Contains(posName, "Комиссар"):    return 2
		case strings.Contains(posName, "Инженер"):     return 3
		default:                                        return 4 // Работник
		}
	}
	// Должности отряда
	switch {
	case strings.Contains(posName, "Командир"):  return 5
	case strings.Contains(posName, "Комиссар"):  return 6
	case strings.Contains(posName, "Мастер"):    return 7 // Инженер отряда по ТЗ
	default:                                      return 8 // Боец / Кандидат
	}
}

// positionDisplayName — «Кандидат» → «Боец» в списке
func positionDisplayName(posName string) string {
	if posName == "Кандидат" || posName == "" { return "Боец" }
	return posName
}

// SendParticipantList — формирует Excel и отправляет на EMAIL_TO
func SendParticipantList(cfg config.Config, eventTitle string, participants []EventParticipant) {
	if cfg.EmailTo == "" || cfg.SMTPUser == "" {
		return
	}
	go func() {
		xlsxBytes, err := buildExcel(eventTitle, participants)
		if err != nil {
			fmt.Printf("[email] excel build failed: %v\n", err)
			return
		}
		// Тема письма = название мероприятия
		if err := sendMailWithAttachment(cfg, eventTitle, xlsxBytes, sanitizeFilename(eventTitle)+".xlsx"); err != nil {
			fmt.Printf("[email] send failed: %v\n", err)
		}
	}()
}

func sanitizeFilename(s string) string {
	r := strings.NewReplacer("/", "-", "\\", "-", ":", "-", "*", "-",
		"?", "-", "\"", "-", "<", "-", ">", "-", "|", "-")
	return r.Replace(s)
}

// buildExcel — строит .xlsx файл со списком участников
func buildExcel(eventTitle string, participants []EventParticipant) ([]byte, error) {
	f := excelize.NewFile()
	defer f.Close()

	sheet := "Участники"
	f.SetSheetName("Sheet1", sheet)

	// Общий стиль данных: Times New Roman 12, центр по обоим осям, перенос
	centerStyle, err := f.NewStyle(&excelize.Style{
		Font: &excelize.Font{Family: "Times New Roman", Size: 12},
		Alignment: &excelize.Alignment{
			Horizontal: "center",
			Vertical:   "center",
			WrapText:   true,
		},
		Border: []excelize.Border{
			{Type: "left",   Color: "000000", Style: 1},
			{Type: "right",  Color: "000000", Style: 1},
			{Type: "top",    Color: "000000", Style: 1},
			{Type: "bottom", Color: "000000", Style: 1},
		},
	})
	if err != nil { return nil, err }

	// Стиль шапки: жирный + синяя заливка
	headerStyle, err := f.NewStyle(&excelize.Style{
		Font: &excelize.Font{Family: "Times New Roman", Size: 12, Bold: true},
		Alignment: &excelize.Alignment{
			Horizontal: "center",
			Vertical:   "center",
			WrapText:   true,
		},
		Fill: excelize.Fill{
			Type:    "pattern",
			Color:   []string{"#D9E1F2"},
			Pattern: 1,
		},
		Border: []excelize.Border{
			{Type: "left",   Color: "000000", Style: 2},
			{Type: "right",  Color: "000000", Style: 2},
			{Type: "top",    Color: "000000", Style: 2},
			{Type: "bottom", Color: "000000", Style: 2},
		},
	})
	if err != nil { return nil, err }

	// Стиль заголовка документа
	titleStyle, _ := f.NewStyle(&excelize.Style{
		Font:      &excelize.Font{Family: "Times New Roman", Size: 13, Bold: true},
		Alignment: &excelize.Alignment{Horizontal: "center", Vertical: "center"},
	})

	// Строка 1 — название мероприятия
	f.SetCellValue(sheet, "A1", "Список участников: "+eventTitle)
	f.MergeCell(sheet, "A1", "H1")
	f.SetCellStyle(sheet, "A1", "H1", titleStyle)
	f.SetRowHeight(sheet, 1, 28)

	// Строка 2 — дата и количество
	f.SetCellValue(sheet, "A2",
		fmt.Sprintf("Сформирован: %s  |  Всего участников: %d",
			time.Now().Format("02.01.2006 15:04"), len(participants)))
	f.MergeCell(sheet, "A2", "H2")
	f.SetCellStyle(sheet, "A2", "H2", centerStyle)
	f.SetRowHeight(sheet, 2, 20)

	// Строка 3 — шапка таблицы (ТОЧНО по ТЗ)
	headers := []string{
		"№ п/п",
		"Название мероприятия",
		"№ чл. билета",
		"ФИО",
		"Учебное заведение",
		"Отряд",
		"Должность",
		"Контактный телефон",
	}
	cols := []string{"A", "B", "C", "D", "E", "F", "G", "H"}
	widths := []float64{6, 28, 14, 32, 24, 28, 20, 18}

	for i, h := range headers {
		cell := cols[i] + "3"
		f.SetCellValue(sheet, cell, h)
		f.SetCellStyle(sheet, cell, cell, headerStyle)
		f.SetColWidth(sheet, cols[i], cols[i], widths[i])
	}
	f.SetRowHeight(sheet, 3, 38)

	// Строки данных начиная с 4
	for i, p := range participants {
		row := i + 4
		fio := strings.TrimSpace(p.LastName + " " + p.FirstName + " " + p.MiddleName)

		values := []interface{}{
			p.Num,
			p.EventTitle,
			p.CardNumber,
			fio,
			p.Institution,
			p.UnitName,
			positionDisplayName(p.PositionName),
			p.Phone,
		}
		for j, v := range values {
			cell := cols[j] + fmt.Sprint(row)
			f.SetCellValue(sheet, cell, v)
			f.SetCellStyle(sheet, cell, cell, centerStyle)
		}
		f.SetRowHeight(sheet, row, 22)
	}

	// Заморозка строк заголовка
	f.SetPanes(sheet, &excelize.Panes{
		Freeze:      true,
		YSplit:      3,
		TopLeftCell: "A4",
		ActivePane:  "bottomLeft",
	})

	var buf bytes.Buffer
	if err := f.Write(&buf); err != nil { return nil, err }
	return buf.Bytes(), nil
}

// sendMailWithAttachment — письмо с .xlsx вложением
func sendMailWithAttachment(cfg config.Config, subject string,
	attachment []byte, filename string) error {

	boundary := "===============RSOEmailBoundary=="
	b64 := base64.StdEncoding.EncodeToString(attachment)

	// RFC 2045: строки base64 по 76 символов
	var b64Chunked strings.Builder
	for i := 0; i < len(b64); i += 76 {
		end := i + 76
		if end > len(b64) { end = len(b64) }
		b64Chunked.WriteString(b64[i:end] + "\r\n")
	}

	// UTF-8 тема письма через base64 encoded-word
	encodedSubject := "=?UTF-8?B?" + base64.StdEncoding.EncodeToString([]byte(subject)) + "?="

	bodyText := "Список участников мероприятия: " + subject + "\r\nФайл Excel во вложении."

	msg := strings.Join([]string{
		"From: " + cfg.SMTPUser,
		"To: " + cfg.EmailTo,
		"Subject: " + encodedSubject,
		"MIME-Version: 1.0",
		`Content-Type: multipart/mixed; boundary="` + boundary + `"`,
		"",
		"--" + boundary,
		"Content-Type: text/plain; charset=UTF-8",
		"Content-Transfer-Encoding: base64",
		"",
		base64.StdEncoding.EncodeToString([]byte(bodyText)),
		"",
		"--" + boundary,
		"Content-Type: application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
		"Content-Transfer-Encoding: base64",
		`Content-Disposition: attachment; filename="` + filename + `"`,
		"",
		b64Chunked.String(),
		"--" + boundary + "--",
	}, "\r\n")

	auth := smtp.PlainAuth("", cfg.SMTPUser, cfg.SMTPPassword, cfg.SMTPHost)
	addr := fmt.Sprintf("%s:%d", cfg.SMTPHost, cfg.SMTPPort)

	if cfg.SMTPPort == 465 {
		// SSL/TLS (Яндекс, Mail.ru)
		tlsConf := &tls.Config{ServerName: cfg.SMTPHost}
		conn, err := tls.Dial("tcp", addr, tlsConf)
		if err != nil { return fmt.Errorf("tls dial: %w", err) }
		defer conn.Close()
		c, err := smtp.NewClient(conn, cfg.SMTPHost)
		if err != nil { return fmt.Errorf("smtp client: %w", err) }
		if err = c.Auth(auth); err != nil { return fmt.Errorf("smtp auth: %w", err) }
		if err = c.Mail(cfg.SMTPUser); err != nil { return err }
		if err = c.Rcpt(cfg.EmailTo); err != nil { return err }
		w, err := c.Data()
		if err != nil { return err }
		if _, err = fmt.Fprint(w, msg); err != nil { return err }
		if err = w.Close(); err != nil { return err }
		return c.Quit()
	}

	// STARTTLS (Gmail 587 и др.)
	return smtp.SendMail(addr, auth, cfg.SMTPUser, []string{cfg.EmailTo}, []byte(msg))
}