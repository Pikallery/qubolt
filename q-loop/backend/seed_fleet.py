"""Seed driver GPS positions for fleet map demo."""
import asyncio
import os
from sqlalchemy import text
from sqlalchemy.ext.asyncio import create_async_engine

POSITIONS = [
    ("samal@gmail.com", 20.4625, 85.8830, 45, "en_route"),
    ("saisamal@gmail.com", 20.2961, 85.8315, 0, "at_hub"),
    ("dibyanshu@company.com", 21.0561, 86.5129, 62, "en_route"),
    ("ravi@company.com", 21.4942, 86.9355, 38, "en_route"),
    ("ravi.driver@test.com", 19.8106, 85.8315, 0, "idle"),
]

TENANT = "a25c91cf-681c-4381-9122-8c6e807a29c0"

async def main():
    engine = create_async_engine(os.environ["DATABASE_URL"])
    async with engine.begin() as conn:
        r = await conn.execute(text(
            "SELECT id, email FROM users WHERE tenant_id=:tid AND role='driver' AND is_active=true"
        ), {"tid": TENANT})
        drivers = {row[1]: str(row[0]) for row in r.fetchall()}
        print("Found drivers:", list(drivers.keys()))

        for email, lat, lon, speed, status in POSITIONS:
            uid = drivers.get(email)
            if not uid:
                print(f"Skip {email}")
                continue
            cid = f"DRV-OD-TRUCK-{abs(hash(email)) % 9000 + 1000}"
            await conn.execute(text(
                "INSERT INTO driver_locations (tenant_id, driver_id, lat, lon, speed_kmh, status, custom_id) "
                "VALUES (:tid, :did, :lat, :lon, :speed, :status, :cid) "
                "ON CONFLICT ON CONSTRAINT uq_driver_locations_driver "
                "DO UPDATE SET lat=:lat, lon=:lon, speed_kmh=:speed, status=:status, updated_at=now()"
            ), {"tid": TENANT, "did": uid, "lat": lat, "lon": lon, "speed": speed, "status": status, "cid": cid})
            print(f"Seeded {email} at ({lat},{lon}) status={status}")

    await engine.dispose()
    print("Done!")

asyncio.run(main())
