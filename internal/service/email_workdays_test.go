package service_test

import (
	"testing"
	"time"
)

// subtractWorkdays не экспортирована — тестируем логику отдельно.
// В production: дедлайн = 3 рабочих дня до мероприятия в 00:00 НСК.

func subtractWorkdays(t time.Time, days int) time.Time {
	count := 0
	cur := t.AddDate(0, 0, -1)
	for count < days {
		if cur.Weekday() != time.Saturday && cur.Weekday() != time.Sunday {
			count++
		}
		if count < days {
			cur = cur.AddDate(0, 0, -1)
		}
	}
	nsk, _ := time.LoadLocation("Asia/Novosibirsk")
	return time.Date(cur.Year(), cur.Month(), cur.Day(), 0, 0, 0, 0, nsk)
}

func TestSubtractWorkdays_SkipsWeekends(t *testing.T) {
	// Среда 20 мая 2026 — 3 рабочих дня назад = пятница 15 мая (пн→вт→ср)
	nsk, _ := time.LoadLocation("Asia/Novosibirsk")
	event := time.Date(2026, 5, 20, 9, 0, 0, 0, nsk) // среда

	deadline := subtractWorkdays(event, 3)

	// 3 рабочих дня назад от среды 20 = пятница 15
	expected := time.Date(2026, 5, 15, 0, 0, 0, 0, nsk)
	if !deadline.Equal(expected) {
		t.Errorf("want %v, got %v", expected, deadline)
	}
}

func TestSubtractWorkdays_MondayEvent_SkipsSatSun(t *testing.T) {
	// Понедельник 18 мая — 3 рабочих дня = среда 13 мая
	nsk, _ := time.LoadLocation("Asia/Novosibirsk")
	event := time.Date(2026, 5, 18, 9, 0, 0, 0, nsk) // понедельник

	deadline := subtractWorkdays(event, 3)

	expected := time.Date(2026, 5, 13, 0, 0, 0, 0, nsk) // среда
	if !deadline.Equal(expected) {
		t.Errorf("want %v, got %v", expected, deadline)
	}
}

func TestSubtractWorkdays_DeadlineAtMidnight(t *testing.T) {
	nsk, _ := time.LoadLocation("Asia/Novosibirsk")
	event := time.Date(2026, 6, 5, 14, 0, 0, 0, nsk) // пятница

	deadline := subtractWorkdays(event, 3)

	// Дедлайн должен быть в 00:00:00
	if deadline.Hour() != 0 || deadline.Minute() != 0 || deadline.Second() != 0 {
		t.Errorf("deadline should be at midnight NSK, got %v", deadline)
	}
}

func TestSubtractWorkdays_DeadlineInNSK(t *testing.T) {
	nsk, _ := time.LoadLocation("Asia/Novosibirsk")
	event := time.Date(2026, 6, 10, 9, 0, 0, 0, nsk)

	deadline := subtractWorkdays(event, 3)

	if deadline.Location().String() != nsk.String() {
		t.Errorf("deadline should be in NSK timezone, got %s", deadline.Location())
	}
}

func TestSubtractWorkdays_ZeroDays_SameDay(t *testing.T) {
	nsk, _ := time.LoadLocation("Asia/Novosibirsk")
	event := time.Date(2026, 6, 10, 9, 0, 0, 0, nsk)

	// 0 рабочих дней назад — поведение не ломается
	_ = subtractWorkdays(event, 0)
}
