"""
locustfile.py — Online Boutique (Service Weaver) Load Test Script
=================================================================
Simulates realistic user flows for the Online Boutique application.

Usage:
  # Headless (used by experiment runner scripts):
  locust -f locustfile.py --headless \
         -u 500 -r 50 --run-time 300s \
         --host http://localhost:8080 \
         --csv results/run_prefix

  # Interactive web UI (for manual testing):
  locust -f locustfile.py --host http://localhost:8080

User flows implemented:
  1. Browse home page
  2. List products
  3. View product detail
  4. Add to cart
  5. View cart
  6. Simulate checkout (submits checkout form)
  7. Currency change
  8. View recommendations
"""

import random
from locust import HttpUser, task, between, events
from locust.exception import StopUser


# ── Product catalogue (must match the Online Boutique seeded products) ─────────
PRODUCT_IDS = [
    "OLJCESPC7Z",  # Sunglasses
    "66VCHSJNUP",  # Tank Top
    "1YMWWN1N4O",  # Watch
    "L9ECAV7KIM",  # Loafers
    "2ZYFJ3GM2N",  # Hairdryer
    "0PUK6V6EV0",  # Candle Holder
    "LS4PSXUNUM",  # Salt & Pepper Shakers
    "9SIQT8TOJO",  # Bamboo Glass Jar
    "6E92ZMYYFZ",  # Mug
]

# ── Fake checkout form data ────────────────────────────────────────────────────
FIRST_NAMES  = ["Alice", "Bob", "Carol", "Dave", "Eve", "Frank", "Grace"]
LAST_NAMES   = ["Smith", "Jones", "Brown", "Davis", "Moore", "Taylor"]
EMAIL_DOMAINS = ["example.com", "test.org", "demo.net"]
CREDIT_CARDS  = ["4432-8015-6152-0454", "4913-2507-1630-9628", "4024-0071-1108-0491"]
CURRENCIES    = ["USD", "EUR", "GBP", "JPY", "CAD", "INR"]


def _fake_checkout_data():
    """Return randomised but structurally valid checkout form fields."""
    fn = random.choice(FIRST_NAMES)
    ln = random.choice(LAST_NAMES)
    return {
        "email":               f"{fn.lower()}.{ln.lower()}@{random.choice(EMAIL_DOMAINS)}",
        "street_address":      f"{random.randint(1, 999)} Main St",
        "zip_code":            f"{random.randint(10000, 99999)}",
        "city":                "Testville",
        "state":               "CA",
        "country":             "United States",
        "credit_card_number":  random.choice(CREDIT_CARDS),
        "credit_card_expiration_month": str(random.randint(1, 12)),
        "credit_card_expiration_year":  str(random.randint(2026, 2030)),
        "credit_card_cvv":     str(random.randint(100, 999)),
    }


# ── Locust User ────────────────────────────────────────────────────────────────
class BoutiqueUser(HttpUser):
    """
    Simulates a realistic Online Boutique visitor.
    Wait between 1 and 5 seconds between requests to mimic human behaviour.
    """
    wait_time = between(1, 5)

    # ── Helper ─────────────────────────────────────────────────────────────────
    def _random_product(self):
        return random.choice(PRODUCT_IDS)

    # ── Tasks (weights control relative frequency) ─────────────────────────────

    @task(10)
    def view_homepage(self):
        """Browse the main landing page."""
        with self.client.get("/", name="GET /", catch_response=True) as resp:
            if resp.status_code not in (200, 301, 302):
                resp.failure(f"Unexpected status {resp.status_code}")

    @task(8)
    def list_products(self):
        """Simulate browsing the product catalogue (home = product list)."""
        currency = random.choice(CURRENCIES)
        with self.client.get(
            "/", params={"currency": currency}, name="GET /?currency=X",
            catch_response=True
        ) as resp:
            if resp.status_code not in (200, 301, 302):
                resp.failure(f"Unexpected status {resp.status_code}")

    @task(7)
    def view_product(self):
        """View a random product detail page."""
        pid = self._random_product()
        with self.client.get(
            f"/product/{pid}", name="GET /product/[id]",
            catch_response=True
        ) as resp:
            if resp.status_code not in (200, 301, 302):
                resp.failure(f"Unexpected status {resp.status_code}")

    @task(5)
    def add_to_cart(self):
        """Add a random product to the cart."""
        pid = self._random_product()
        with self.client.post(
            "/cart",
            data={"product_id": pid, "quantity": random.randint(1, 3)},
            name="POST /cart (add)",
            catch_response=True,
        ) as resp:
            if resp.status_code not in (200, 201, 302):
                resp.failure(f"Unexpected status {resp.status_code}")

    @task(4)
    def view_cart(self):
        """View the shopping cart."""
        with self.client.get("/cart", name="GET /cart", catch_response=True) as resp:
            if resp.status_code not in (200, 301, 302):
                resp.failure(f"Unexpected status {resp.status_code}")

    @task(2)
    def checkout(self):
        """
        Full checkout flow:
          1. Add a product to cart
          2. Post checkout form
        """
        # Step 1 – ensure something is in cart
        pid = self._random_product()
        self.client.post(
            "/cart",
            data={"product_id": pid, "quantity": 1},
            name="POST /cart (pre-checkout add)",
        )
        # Step 2 – submit checkout
        data = _fake_checkout_data()
        with self.client.post(
            "/cart/checkout",
            data=data,
            name="POST /cart/checkout",
            catch_response=True,
            allow_redirects=True,
        ) as resp:
            if resp.status_code not in (200, 302, 303):
                resp.failure(f"Checkout failed: {resp.status_code}")

    @task(3)
    def change_currency(self):
        """Change the display currency."""
        with self.client.post(
            "/setCurrency",
            data={"currency_code": random.choice(CURRENCIES)},
            name="POST /setCurrency",
            catch_response=True,
        ) as resp:
            if resp.status_code not in (200, 302, 303):
                resp.failure(f"setCurrency failed: {resp.status_code}")

    @task(2)
    def empty_cart(self):
        """Empty the cart (simulates abandoned cart)."""
        with self.client.post(
            "/cart/empty",
            name="POST /cart/empty",
            catch_response=True,
        ) as resp:
            if resp.status_code not in (200, 302, 303):
                resp.failure(f"empty cart failed: {resp.status_code}")

    @task(1)
    def get_ads(self):
        """Hit the /ads endpoint directly (ad service test)."""
        pid = self._random_product()
        with self.client.get(
            "/", params={"product_id": pid}, name="GET /?product_id=X",
            catch_response=True,
        ) as resp:
            if resp.status_code not in (200, 301, 302):
                resp.failure(f"Unexpected status {resp.status_code}")


# ── Event hooks for CSV timestamping ──────────────────────────────────────────
@events.test_start.add_listener
def on_test_start(environment, **kwargs):
    print(f"[locust] Test starting → target: {environment.host}")


@events.test_stop.add_listener
def on_test_stop(environment, **kwargs):
    print("[locust] Test complete.")
