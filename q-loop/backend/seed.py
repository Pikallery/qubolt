"""
Bootstrap script — creates the demo tenant + admin user, then prints a JWT.
Run inside the backend container:
    python seed.py
"""
import asyncio
import uuid
from app.core.database import AsyncSessionLocal
from app.core.security import hash_password, create_access_token
from app.models.tenant import Tenant
from app.models.user import User
from sqlalchemy import select


TENANT_NAME  = "Q-Loop Demo"
ADMIN_EMAIL  = "admin@qloop.io"
ADMIN_PASS   = "Admin1234!"
ADMIN_ROLE   = "admin"


async def seed():
    async with AsyncSessionLocal() as db:
        # ── Tenant ────────────────────────────────────────────────────────────
        res = await db.execute(select(Tenant).where(Tenant.name == TENANT_NAME))
        tenant = res.scalar_one_or_none()
        if not tenant:
            tenant = Tenant(name=TENANT_NAME, slug="qloop-demo", plan="enterprise")
            db.add(tenant)
            await db.flush()
            print(f"[+] Tenant created: {tenant.id}")
        else:
            print(f"[=] Tenant exists:  {tenant.id}")

        # ── Admin user ────────────────────────────────────────────────────────
        res = await db.execute(
            select(User).where(User.tenant_id == tenant.id, User.email == ADMIN_EMAIL)
        )
        user = res.scalar_one_or_none()
        if not user:
            user = User(
                tenant_id=tenant.id,
                email=ADMIN_EMAIL,
                hashed_password=hash_password(ADMIN_PASS),
                full_name="Q-Loop Admin",
                role=ADMIN_ROLE,
            )
            db.add(user)
            await db.flush()
            print(f"[+] User created:   {user.id}")
        else:
            print(f"[=] User exists:    {user.id}")

        await db.commit()

        # ── Print JWT ─────────────────────────────────────────────────────────
        token = create_access_token(str(user.id), str(tenant.id), ADMIN_ROLE)
        print(f"\nTENANT_ID={tenant.id}")
        print(f"JWT={token}\n")


if __name__ == "__main__":
    asyncio.run(seed())
