"""
One-off script used to generate the synthetic data checked into data/csv/.
Not part of the normal setup flow (use load_data.py for that) — kept here
for transparency on how the sample dataset was produced.
"""
import sqlite3, random, datetime, os

random.seed(7)
HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DB = os.path.join(HERE, "data", "ecommerce_generator_scratch.db")
if os.path.exists(DB):
    os.remove(DB)
conn = sqlite3.connect(DB)
cur = conn.cursor()
cur.executescript("""
PRAGMA foreign_keys = ON;

CREATE TABLE customers (
    customer_id    INTEGER PRIMARY KEY,
    first_name     TEXT NOT NULL,
    last_name      TEXT NOT NULL,
    city            TEXT NOT NULL,
    country         TEXT NOT NULL,
    signup_date     TEXT NOT NULL,
    acquisition_channel TEXT NOT NULL CHECK (acquisition_channel IN ('Organic Search','Paid Social','Email','Referral','Direct'))
);

CREATE TABLE categories (
    category_id    INTEGER PRIMARY KEY,
    category_name  TEXT NOT NULL
);

CREATE TABLE products (
    product_id     INTEGER PRIMARY KEY,
    product_name   TEXT NOT NULL,
    category_id    INTEGER NOT NULL REFERENCES categories(category_id),
    unit_price     REAL NOT NULL,
    unit_cost      REAL NOT NULL
);

CREATE TABLE orders (
    order_id       INTEGER PRIMARY KEY,
    customer_id    INTEGER NOT NULL REFERENCES customers(customer_id),
    order_date     TEXT NOT NULL,
    status         TEXT NOT NULL CHECK (status IN ('Completed','Cancelled','Returned')),
    payment_method TEXT NOT NULL CHECK (payment_method IN ('Card','PayPal','Bank Transfer','Gift Card'))
);

CREATE TABLE order_items (
    order_item_id  INTEGER PRIMARY KEY,
    order_id       INTEGER NOT NULL REFERENCES orders(order_id),
    product_id     INTEGER NOT NULL REFERENCES products(product_id),
    quantity       INTEGER NOT NULL,
    unit_price     REAL NOT NULL   -- price at time of sale, can differ from products.unit_price
);

CREATE TABLE reviews (
    review_id      INTEGER PRIMARY KEY,
    product_id     INTEGER NOT NULL REFERENCES products(product_id),
    customer_id    INTEGER NOT NULL REFERENCES customers(customer_id),
    rating         INTEGER NOT NULL CHECK (rating BETWEEN 1 AND 5),
    review_date    TEXT NOT NULL
);

CREATE INDEX idx_orders_customer ON orders(customer_id);
CREATE INDEX idx_orders_date ON orders(order_date);
CREATE INDEX idx_items_order ON order_items(order_id);
CREATE INDEX idx_items_product ON order_items(product_id);
CREATE INDEX idx_reviews_product ON reviews(product_id);
""")

first_names = ["Olivia","Liam","Emma","Noah","Ava","Ethan","Sophia","Mason","Isabella","Lucas",
               "Mia","James","Amelia","Benjamin","Harper","Alexander","Evelyn","Michael","Abigail","Daniel",
               "Priya","Rahul","Ananya","Karan","Neha","Arjun","Sara","Omar","Fatima","Yusuf",
               "Chloe","Jack","Grace","Henry","Zoe","Leo","Ella","Sam","Ruby","Max"]
last_names = ["Smith","Johnson","Williams","Brown","Jones","Garcia","Miller","Davis","Martinez","Wilson",
              "Anderson","Taylor","Thomas","Moore","Jackson","Martin","Lee","Perez","Thompson","White",
              "Sharma","Patel","Khan","Gupta","Nair","Reddy","Iyer","Chowdhury","Rao","Desai"]
cities_countries = [
    ("London","UK"),("Manchester","UK"),("Birmingham","UK"),("Leeds","UK"),
    ("Mumbai","India"),("Bangalore","India"),("Pune","India"),("Delhi","India"),
    ("New York","USA"),("Chicago","USA"),("Austin","USA"),
    ("Toronto","Canada"),("Sydney","Australia"),("Dublin","Ireland"),
]
channels = ["Organic Search","Paid Social","Email","Referral","Direct"]

def rand_date(start, end):
    delta = (end-start).days
    return (start + datetime.timedelta(days=random.randint(0, delta))).isoformat()

today = datetime.date(2026,9,14)
signup_start = datetime.date(2023,1,1)

# ---------- Customers ----------
N_CUST = 600
customers = []
for cid in range(1, N_CUST+1):
    fn, ln = random.choice(first_names), random.choice(last_names)
    city, country = random.choice(cities_countries)
    signup = rand_date(signup_start, today)
    channel = random.choices(channels, [0.32,0.22,0.18,0.13,0.15])[0]
    customers.append((cid, fn, ln, city, country, signup, channel))
cur.executemany("INSERT INTO customers VALUES (?,?,?,?,?,?,?)", customers)

# ---------- Categories & products ----------
categories = [(1,"Electronics"),(2,"Home & Kitchen"),(3,"Sportswear"),(4,"Books"),
              (5,"Beauty"),(6,"Toys"),(7,"Footwear"),(8,"Office Supplies")]
cur.executemany("INSERT INTO categories VALUES (?,?)", categories)

product_names = {
    1: ["Wireless Earbuds","Bluetooth Speaker","4K Monitor","USB-C Hub","Smart Watch","Laptop Stand","Mechanical Keyboard","Webcam HD"],
    2: ["Non-stick Pan Set","Electric Kettle","Air Fryer","Cutlery Set","Ceramic Mug Set","Blender","Storage Jars","Dish Rack"],
    3: ["Running Shorts","Yoga Mat","Resistance Bands","Gym Duffel Bag","Compression Leggings","Water Bottle","Foam Roller","Training Gloves"],
    4: ["Data Analysis Handbook","Historical Fiction Novel","Cookbook: World Cuisine","Personal Finance Guide","Sci-Fi Anthology","Business Strategy Book"],
    5: ["Facial Cleanser","Vitamin C Serum","Sunscreen SPF50","Hair Dryer","Lip Balm Set","Shampoo & Conditioner Kit"],
    6: ["Building Blocks Set","Puzzle 1000pc","Remote Control Car","Plush Toy Bear","Board Game Classic"],
    7: ["Running Shoes","Canvas Sneakers","Leather Loafers","Hiking Boots","Sandals"],
    8: ["Notebook Pack","Ergonomic Mouse","Desk Organizer","Sticky Notes Set","Printer Paper Ream"],
}
products = []
pid = 1
for cat_id, names in product_names.items():
    for name in names:
        cost = round(random.uniform(5, 120), 2)
        price = round(cost * random.uniform(1.4, 2.6), 2)
        products.append((pid, name, cat_id, price, cost))
        pid += 1
cur.executemany("INSERT INTO products VALUES (?,?,?,?,?)", products)
N_PROD = pid - 1

# ---------- Orders & order_items ----------
orders = []
order_items = []
oid = 1
oiid = 1
payment_methods = ["Card","PayPal","Bank Transfer","Gift Card"]
for cid, fn, ln, city, country, signup, channel in customers:
    signup_date = datetime.date.fromisoformat(signup)
    # repeat-purchase behaviour varies by customer
    n_orders = random.choices([0,1,2,3,4,5,8,12],[0.08,0.18,0.20,0.18,0.14,0.10,0.08,0.04])[0]
    for _ in range(n_orders):
        span = (today - signup_date).days
        if span <= 0:
            continue
        odate = signup_date + datetime.timedelta(days=random.randint(0, span))
        status = random.choices(["Completed","Cancelled","Returned"], [0.86,0.07,0.07])[0]
        pay = random.choice(payment_methods)
        orders.append((oid, cid, odate.isoformat(), status, pay))
        n_items = random.choices([1,2,3,4],[0.45,0.30,0.17,0.08])[0]
        chosen = random.sample(range(1, N_PROD+1), n_items)
        for p_id in chosen:
            base_price = next(p[3] for p in products if p[0] == p_id)
            price = round(base_price * random.uniform(0.9, 1.05), 2)
            qty = random.choices([1,2,3],[0.7,0.22,0.08])[0]
            order_items.append((oiid, oid, p_id, qty, price))
            oiid += 1
        oid += 1
cur.executemany("INSERT INTO orders VALUES (?,?,?,?,?)", orders)
cur.executemany("INSERT INTO order_items VALUES (?,?,?,?,?)", order_items)

# ---------- Reviews ----------
reviews = []
rid = 1
completed_orders = [o for o in orders if o[3] == "Completed"]
for o in completed_orders:
    if random.random() < 0.35:
        order_id = o[0]
        cid = o[1]
        items_for_order = [it for it in order_items if it[1] == order_id]
        if not items_for_order:
            continue
        item = random.choice(items_for_order)
        rating = random.choices([5,4,3,2,1],[0.42,0.30,0.15,0.08,0.05])[0]
        rdate = (datetime.date.fromisoformat(o[2]) + datetime.timedelta(days=random.randint(1,21))).isoformat()
        reviews.append((rid, item[2], cid, rating, rdate))
        rid += 1
cur.executemany("INSERT INTO reviews VALUES (?,?,?,?,?)", reviews)

conn.commit()
print("customers:", len(customers))
print("categories:", len(categories))
print("products:", len(products))
print("orders:", len(orders))
print("order_items:", len(order_items))
print("reviews:", len(reviews))
conn.close()
