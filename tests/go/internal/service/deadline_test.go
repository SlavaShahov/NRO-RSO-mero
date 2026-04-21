package service_test

import (
	"testing"
	"time"
)

// Точные копии функций из service.go
func subtractWorkdays(t time.Time, n int) time.Time {
	r := t
	for i := 0; i < n; {
		r = r.AddDate(0, 0, -1)
		// Пропускаем субботу и воскресенье
		if r.Weekday() != time.Saturday && r.Weekday() != time.Sunday {
			i++
		}
	}
	return r
}

func deadlineFor(eventDate time.Time) time.Time {
	ld := subtractWorkdays(eventDate, 3)
	return time.Date(ld.Year(), ld.Month(), ld.Day(), 23, 59, 59, 0, time.UTC)
}

func closed(now, event time.Time) bool { return now.After(deadlineFor(event)) }

// ── По дням недели ────────────────────────────────────────────────────────────

func TestDeadline_Sunday(t *testing.T) {
	// Вс 19 апр 2026: -3 раб.дня → пт16(1) чт15(2) ср14(3) → дедлайн вт14 нет, ср14 нет
	// пт(1)→чт(2)→ср(3) = 14 апр
	event := date(2026, 4, 19)
	assertWeekday(t, event, time.Sunday)
	assertDeadline(t, event, date(2026, 4, 14))
}

func TestDeadline_Monday(t *testing.T) {
	// Пн 20 апр: пт17(1)→чт16(2)→ср15(3) = 15 апр
	event := date(2026, 4, 20)
	assertWeekday(t, event, time.Monday)
	assertDeadline(t, event, date(2026, 4, 15))
}

func TestDeadline_Tuesday(t *testing.T) {
	// Вт 21 апр: пн20(1)→пт17(2)→чт16(3) = 16 апр
	event := date(2026, 4, 21)
	assertWeekday(t, event, time.Tuesday)
	assertDeadline(t, event, date(2026, 4, 16))
}

func TestDeadline_Wednesday(t *testing.T) {
	// Ср 22 апр: вт21(1)→пн20(2)→пт17(3) = 17 апр
	event := date(2026, 4, 22)
	assertWeekday(t, event, time.Wednesday)
	assertDeadline(t, event, date(2026, 4, 17))
}

func TestDeadline_Thursday(t *testing.T) {
	// Чт 23 апр: ср22(1)→вт21(2)→пн20(3) = 20 апр
	event := date(2026, 4, 23)
	assertWeekday(t, event, time.Thursday)
	assertDeadline(t, event, date(2026, 4, 20))
}

func TestDeadline_Friday(t *testing.T) {
	// Пт 24 апр: чт23(1)→ср22(2)→вт21(3) = 21 апр
	event := date(2026, 4, 24)
	assertWeekday(t, event, time.Friday)
	assertDeadline(t, event, date(2026, 4, 21))
}

func TestDeadline_Saturday(t *testing.T) {
	// Сб 25 апр: пт24(1)→чт23(2)→ср22(3) = 22 апр
	event := date(2026, 4, 25)
	assertWeekday(t, event, time.Saturday)
	assertDeadline(t, event, date(2026, 4, 22))
}

// ── Пограничные случаи ────────────────────────────────────────────────────────

func TestDeadline_LastDay_MorningAllowed(t *testing.T) {
	// Пн 20 апр → дедлайн ср 15 апр 23:59:59
	// В 09:00 — ещё открыто
	if closed(datetime(2026, 4, 15, 9, 0, 0), date(2026, 4, 20)) {
		t.Error("15 апр 09:00 должно быть ОТКРЫТО")
	}
}

func TestDeadline_LastDay_235958_Allowed(t *testing.T) {
	if closed(datetime(2026, 4, 15, 23, 59, 58), date(2026, 4, 20)) {
		t.Error("15 апр 23:59:58 должно быть ОТКРЫТО")
	}
}

func TestDeadline_ExactDeadline_Allowed(t *testing.T) {
	// Ровно в 23:59:59 — .After() возвращает false, т.е. ещё открыто
	event := date(2026, 4, 20)
	dl := deadlineFor(event)
	if closed(dl, event) {
		t.Error("точно в дедлайн должно быть ОТКРЫТО (After = строго больше)")
	}
}

func TestDeadline_OneSecondAfter_Closed(t *testing.T) {
	event := date(2026, 4, 20)
	dl := deadlineFor(event)
	if !closed(dl.Add(time.Second), event) {
		t.Error("на секунду после дедлайна должно быть ЗАКРЫТО")
	}
}

func TestDeadline_NextDay_Closed(t *testing.T) {
	// 16 апр — закрыто
	if !closed(datetime(2026, 4, 16, 0, 0, 0), date(2026, 4, 20)) {
		t.Error("16 апр должно быть ЗАКРЫТО")
	}
}

func TestDeadline_EventDay_Closed(t *testing.T) {
	event := date(2026, 4, 20)
	if !closed(event, event) {
		t.Error("в день мероприятия должно быть ЗАКРЫТО")
	}
}

func TestDeadline_DeadlineNeverOnWeekend(t *testing.T) {
	// Проверяем 30 дней подряд — дедлайн никогда не падает на сб/вс
	start := date(2026, 4, 1)
	for i := 0; i < 30; i++ {
		event := start.AddDate(0, 0, i)
		dl := deadlineFor(event)
		wd := dl.Weekday()
		if wd == time.Saturday || wd == time.Sunday {
			t.Errorf("дедлайн для %v = %v (%s) — выходной!", event.Format("02.01"), dl.Format("02.01"), wd)
		}
	}
}

// ── subtractWorkdays edge cases ───────────────────────────────────────────────

func TestSubtract_Zero(t *testing.T) {
	d := date(2026, 4, 20)
	if !subtractWorkdays(d, 0).Equal(d) { t.Error("subtract 0 = same date") }
}

func TestSubtract_MondayMinus1_EqualsFriday(t *testing.T) {
	mon := date(2026, 4, 20)
	fri := date(2026, 4, 17)
	if !subtractWorkdays(mon, 1).Equal(fri) {
		t.Errorf("Mon - 1 workday should be Fri, got %v", subtractWorkdays(mon, 1))
	}
}

func TestSubtract_SkipsFullWeekend(t *testing.T) {
	// Пн 20 апр 2026 - 5 рабочих дней = Пн 13 апр 2026?
	// 20 -> 17 (пт) [1], 16 (чт) [2], 15 (ср) [3], 14 (вт) [4], 13 (пн) [5]
	mon := date(2026, 4, 20)
	want := date(2026, 4, 13) // Понедельник 13 апреля
	got := subtractWorkdays(mon, 5)
	if !got.Equal(want) {
		t.Errorf("Mon - 5 workdays = %s, want %s", got.Format("02.01"), want.Format("02.01"))
	}
}

// ── Helpers ───────────────────────────────────────────────────────────────────

func date(y, m, d int) time.Time {
	return time.Date(y, time.Month(m), d, 0, 0, 0, 0, time.UTC)
}
func datetime(y, m, d, h, min, s int) time.Time {
	return time.Date(y, time.Month(m), d, h, min, s, 0, time.UTC)
}
func assertWeekday(t *testing.T, d time.Time, want time.Weekday) {
	t.Helper()
	if d.Weekday() != want { t.Fatalf("test setup: %v is not %s", d.Format("02.01.06"), want) }
}
func assertDeadline(t *testing.T, event, wantLastDay time.Time) {
	t.Helper()
	want := time.Date(wantLastDay.Year(), wantLastDay.Month(), wantLastDay.Day(),
		23, 59, 59, 0, time.UTC)
	got := deadlineFor(event)
	if !got.Equal(want) {
		t.Errorf("event %s: deadline = %s, want %s",
			event.Format("02.01(Mon)"),
			got.Format("02.01(Mon) 15:04:05"),
			want.Format("02.01(Mon) 15:04:05"))
	}
}
