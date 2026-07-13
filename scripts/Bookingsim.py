
# Booking simuleringer med mulig overlapp KUN når det er ulike lanes:
# - Ingen overlapp innen samme lane
# - Overlapp mellom 4-lane og 2-lane er lov
# - "Ledig tid" ikke inkludert, fordi tider i mellom bookinger regnes
#   som dette. 

import csv
import random
from datetime import date, time, timedelta

# -----------------------------
# Konfigurasjon
# -----------------------------
OPEN_HOUR = 9
CLOSE_HOUR = 23

MIN_BOOKINGS_PER_DAY = 2
MAX_BOOKINGS_PER_DAY = 10

MIN_DURATION_HOURS = 1
MAX_DURATION_HOURS = 3

# Sette periode:
START_DATE = date(2026, 2, 8)
END_DATE = date(2026, 3, 26)
NUM_DAYS = (END_DATE - START_DATE).days + 1

OUTPUT_FILENAME = "NY_2026_simulerte_bookinger.csv"

TIME_STEP_MINUTES = 30

# Brukergrupper (fjerner "Ledig tid")
GROUPS = [
    "Ikke tilgjengelig",
    "Booking",
    "Turnering",
    "Trening",
    "Kurs",
    "Divisjonsspill",
    "Pensjonister",
]

# Vekting:
# - Ikke tilgjengelig + alle tider i mellom bookinger (ledig tid) = Idle 
# - Booking + Kurs + Pensjonister = Hobby
# - Turnering + Trening + Divisjon = Elite
p_ikke_tilg = 0.01

p_booking = 0.29 
p_kurs = 0.20      
p_pensjonister = 0.20 

p_turnering = 0.10  
p_trening = 0.10    
p_divisjon = 0.10    

GROUP_WEIGHTS = {
    "Ikke tilgjengelig": p_ikke_tilg,
    "Booking": p_booking,
    "Kurs": p_kurs,
    "Pensjonister": p_pensjonister,
    "Turnering": p_turnering,
    "Trening": p_trening,
    "Divisjonsspill": p_divisjon,
}

LANES = ["4-lane", "2-lane"]
LANE_WEIGHTS = [0.8, 0.2]

random.seed(42)


# -----------------------------
# Hjelpefunksjoner
# -----------------------------
def weighted_choice(options, weights_map):
    weights = [weights_map[o] for o in options]
    return random.choices(options, weights=weights, k=1)[0]


def minutes_from_hour(h):
    return h * 60


def to_time(mins):
    return time(mins // 60, mins % 60)


def fmt_time(t):
    return t.strftime("%H:%M")


def ceil_to_step(mins, step):
    return ((mins + step - 1) // step) * step


def possible_starts_in_slot(slot_start, slot_end, dur_mins):
    start_min = ceil_to_step(slot_start, TIME_STEP_MINUTES)
    latest_start = slot_end - dur_mins
    if start_min > latest_start:
        return []
    return list(range(start_min, latest_start + 1, TIME_STEP_MINUTES))


def place_one_booking(free_slots, dur_hours):
    dur_mins = dur_hours * 60

    candidates = []
    for (a, b) in free_slots:
        starts = possible_starts_in_slot(a, b, dur_mins)
        if starts:
            candidates.append((a, b, starts))

    if not candidates:
        return None

    a, b, starts = random.choice(candidates)
    start_min = random.choice(starts)
    end_min = start_min + dur_mins

    free_slots.remove((a, b))

    if a < start_min:
        free_slots.append((a, start_min))

    if end_min < b:
        free_slots.append((end_min, b))

    free_slots.sort()

    return start_min, end_min


# -----------------------------
# Generering
# -----------------------------
def generate_day_schedule():
    target = random.randint(MIN_BOOKINGS_PER_DAY, MAX_BOOKINGS_PER_DAY)

    lane_slots = {
        "4-lane": [(minutes_from_hour(OPEN_HOUR), minutes_from_hour(CLOSE_HOUR))],
        "2-lane": [(minutes_from_hour(OPEN_HOUR), minutes_from_hour(CLOSE_HOUR))],
    }

    bookings = []

    for _ in range(target):
        dur = random.randint(MIN_DURATION_HOURS, MAX_DURATION_HOURS)
        group = weighted_choice(GROUPS, GROUP_WEIGHTS)

        lane = random.choices(LANES, weights=LANE_WEIGHTS, k=1)[0]
        placed = place_one_booking(lane_slots[lane], dur)

        if placed is None:
            fallback_order = [2, 1] if dur == 3 else ([1] if dur == 2 else [])
            for fdur in fallback_order:
                placed = place_one_booking(lane_slots[lane], fdur)
                if placed:
                    dur = fdur
                    break

        if placed is None:
            other_lane = "2-lane" if lane == "4-lane" else "4-lane"
            placed = place_one_booking(lane_slots[other_lane], dur)

            if placed is None:
                fallback_order = [2, 1] if dur == 3 else ([1] if dur == 2 else [])
                for fdur in fallback_order:
                    placed = place_one_booking(lane_slots[other_lane], fdur)
                    if placed:
                        dur = fdur
                        break

            if placed:
                lane = other_lane

        if placed is None:
            break

        start_min, end_min = placed

        bookings.append({
            "start_min": start_min,
            "end_min": end_min,
            "brukergruppe": group,
            "lane": lane,
        })

    bookings.sort(key=lambda x: (x["start_min"], x["lane"]))
    return bookings


def generate_bookings():
    rows = []

    for i in range(NUM_DAYS):
        d = START_DATE + timedelta(days=i)
        day_bookings = generate_day_schedule()

        for b in day_bookings:
            start_t = to_time(b["start_min"])
            end_t = to_time(b["end_min"])

            rows.append({
                "dato": d.isoformat(),
                "starttid": fmt_time(start_t),
                "sluttid": fmt_time(end_t),
                "brukergruppe": b["brukergruppe"],
                "lane": b["lane"],
            })

    return rows


def write_csv(rows, filename):
    fieldnames = ["dato", "starttid", "sluttid", "brukergruppe", "lane"]

    with open(filename, "w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(rows)


if __name__ == "__main__":
    rows = generate_bookings()
    write_csv(rows, OUTPUT_FILENAME)

    print(f"Skrev {len(rows)} bookinger til: {OUTPUT_FILENAME}")
    print(f"Periode: {START_DATE.isoformat()} til {END_DATE.isoformat()} ({NUM_DAYS} dager)")