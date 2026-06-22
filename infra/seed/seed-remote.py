#!/usr/bin/env python3
"""Self-contained demo seed for a FRESH database (e.g. Supabase after Flyway has migrated).
Prints SQL to stdout. Creates ~10 Sydney ethnic-grocery stores, ~40 canonical products, ~75
store_products (staples shared across stores for cross-store comparison), and rating aggregates.
Run via seed-remote.sh, or:  python3 seed-remote.py | psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f -
"""
import uuid, random
random.seed(7)

# canonical name -> (brand, size, category, cuisine, base_price)
CANON = {
    "Aashirvaad Atta":   ("Aashirvaad","5kg","Flour","indian",19.50),
    "Chakki Atta":       ("Vimal","10kg","Flour","indian",24.00),
    "Basmati Rice":      ("Tilda","5kg","Rice","indian",21.00),
    "Sona Masoori Rice": ("India Gate","5kg","Rice","indian",16.50),
    "Idli Rice":         ("Laxmi","5kg","Rice","indian",17.90),
    "Toor Dal":          ("TRS","1kg","Lentils","indian",4.20),
    "Moong Dal":         ("TRS","1kg","Lentils","indian",4.60),
    "Chana Dal":         ("TRS","1kg","Lentils","indian",4.10),
    "Masoor Dal":        ("TRS","1kg","Lentils","indian",3.80),
    "Urad Dal":          ("TRS","1kg","Lentils","indian",5.20),
    "Kabuli Chana":      ("TRS","1kg","Lentils","afghan",4.90),
    "Paneer":            ("Gopi","200g","Dairy","indian",5.00),
    "Pure Ghee":         ("Amul","1kg","Dairy","indian",17.50),
    "Amul Butter":       ("Amul","500g","Dairy","indian",6.40),
    "Mango Lassi":       ("Nanak","1L","Dairy","indian",4.50),
    "Plain Yogurt":      ("Desi","1kg","Dairy","indian",5.50),
    "Turmeric Powder":   ("MDH","200g","Spices","indian",2.80),
    "Chilli Powder":     ("MDH","200g","Spices","indian",3.10),
    "Garam Masala":      ("Everest","100g","Spices","indian",3.40),
    "Cumin Seeds":       ("TRS","200g","Spices","indian",3.00),
    "Coriander Powder":  ("MDH","200g","Spices","indian",2.60),
    "Mustard Seeds":     ("TRS","200g","Spices","bengali",2.40),
    "Mustard Oil":       ("Fortune","1L","Oils","bengali",7.90),
    "Sunflower Oil":     ("Sunola","1L","Oils","indian",6.20),
    "Tamarind Paste":    ("Heera","200g","Condiments","srilankan",3.20),
    "Ginger Garlic Paste":("Ashoka","300g","Condiments","indian",3.60),
    "Mango Pickle":      ("Priya","400g","Condiments","indian",4.30),
    "Haldiram Bhujia":   ("Haldiram","200g","Snacks","indian",3.50),
    "Parle-G Biscuits":  ("Parle","800g","Snacks","indian",4.80),
    "Bombay Mix":        ("Cofresh","400g","Snacks","indian",3.90),
    "Papadum":           ("Lijjat","200g","Snacks","indian",2.90),
    "Vermicelli":        ("Bambino","400g","Snacks","pakistani",2.70),
    "Frozen Samosa":     ("Deep","12pk","Frozen","indian",6.50),
    "Frozen Paratha":    ("Kawan","5pk","Frozen","pakistani",5.40),
    "Okra (Bhindi)":     ("Fresh","500g","Vegetables","indian",4.00),
    "Curry Leaves":      ("Fresh","50g","Vegetables","srilankan",1.80),
    "Green Chilli":      ("Fresh","250g","Vegetables","indian",2.20),
    "Masala Chai":       ("Wagh Bakri","250g","Beverages","indian",5.60),
    "Rooh Afza":         ("Hamdard","750ml","Beverages","pakistani",6.80),
    "Coconut Milk":      ("Kara","400ml","Beverages","srilankan",2.10),
}
STAPLES = ["Aashirvaad Atta", "Basmati Rice", "Toor Dal", "Pure Ghee", "Paneer"]

STORES = [
    ("Patel Cash & Carry", ["indian","bengali"], "George St, Sydney", -33.8688, 151.2093, "Family-run South-Asian grocery since 1998."),
    ("Lahore Supermarket", ["pakistani"], "Haymarket, Sydney", -33.8760, 151.2050, "Pakistani spices, atta, halal & frozen."),
    ("Spice Bazaar", ["indian"], "Harris Park, Sydney", -33.8230, 151.0040, "North & South Indian grocer."),
    ("Dhaka Grocers", ["bengali"], "Lakemba, Sydney", -33.9200, 151.0750, "Authentic Bangladeshi fish, rice & spices."),
    ("Colombo Market", ["srilankan"], "Homebush, Sydney", -33.8650, 151.0860, "Sri Lankan staples, coconut & curry leaves."),
    ("Kabul Foods", ["afghan","pakistani"], "Auburn, Sydney", -33.8490, 151.0330, "Afghan bread, dry fruits & halal goods."),
    ("Himalaya Mart", ["nepali","indian"], "Parramatta, Sydney", -33.8150, 151.0050, "Nepali & Indian pantry essentials."),
    ("Karachi Halal", ["pakistani"], "Granville, Sydney", -33.8330, 151.0120, "Pakistani spices, atta & frozen halal."),
    ("Madras Groceries", ["indian"], "Wentworthville, Sydney", -33.8070, 150.9720, "South Indian rice, dals & filter coffee."),
    ("Bengal Bazaar", ["bengali"], "Strathfield, Sydney", -33.8760, 151.0820, "Bengali sweets, mustard oil & fish."),
]

def key(name, brand, size):
    return ''.join(c for c in (brand + name + size).lower() if c.isalnum())

def q(s):  # sql-escape
    return s.replace("'", "''")

out = ["BEGIN;"]
cid = {}
for n, (brand, size, cat, cuisine, price) in CANON.items():
    i = str(uuid.uuid4()); cid[n] = i
    out.append("INSERT INTO canonical_product (id,name,brand,size_label,category,cuisine_tag,match_key) "
        "VALUES ('%s','%s','%s','%s','%s','%s','%s') ON CONFLICT (match_key) DO NOTHING;" %
        (i, q(n), brand, size, cat, cuisine, key(n, brand, size)))
    avg = round(random.uniform(3.9, 4.9), 1); cnt = random.randint(6, 180)
    out.append("INSERT INTO product_rating_aggregate (canonical_product_id,avg_rating,review_count) "
        "VALUES ('%s',%s,%d) ON CONFLICT (canonical_product_id) DO UPDATE SET avg_rating=EXCLUDED.avg_rating, review_count=EXCLUDED.review_count;" % (i, avg, cnt))

sp = 0
for name, cuisines, addr, lat, lng, desc in STORES:
    oid = str(uuid.uuid4()); sid = str(uuid.uuid4())
    email = "owner_%s@grocery-mart.dev" % ''.join(c for c in name.lower() if c.isalnum())
    out.append("INSERT INTO app_user (id,email,display_name,password_hash,status) VALUES "
        "('%s','%s','%s',crypt('shoppass123',gen_salt('bf')),'active') ON CONFLICT (email) DO NOTHING;" % (oid, email, q(name + " Owner")))
    out.append("INSERT INTO user_role (user_id,role) VALUES ('%s','SHOP_OWNER') ON CONFLICT DO NOTHING;" % oid)
    out.append("INSERT INTO shop (id,owner_id,name,cuisine_tags,status,description,address,is_open,location) VALUES "
        "('%s','%s','%s','{%s}','active','%s','%s',true,ST_SetSRID(ST_MakePoint(%s,%s),4326)::geography);" %
        (sid, oid, q(name), ','.join(cuisines), q(desc), addr, lng, lat))
    out.append("INSERT INTO store_rating_aggregate (shop_id,avg_rating,review_count) VALUES ('%s',%s,%d) "
        "ON CONFLICT (shop_id) DO UPDATE SET avg_rating=EXCLUDED.avg_rating, review_count=EXCLUDED.review_count;" %
        (sid, round(random.uniform(4.1, 4.9), 1), random.randint(24, 360)))
    pool = [n for n in CANON if n not in STAPLES and (CANON[n][3] in cuisines or CANON[n][3] == 'indian')]
    random.shuffle(pool)
    for n in dict.fromkeys(STAPLES + pool[:random.randint(4, 7)]):
        brand, size, base = CANON[n][0], CANON[n][1], CANON[n][4]
        price = round(base * random.uniform(0.88, 1.22), 2)
        out.append("INSERT INTO store_product (shop_id,canonical_product_id,raw_name,raw_brand,raw_size,price_amount,currency,stock,match_status) "
            "VALUES ('%s','%s','%s','%s','%s',%s,'AUD',%d,'auto_linked');" % (sid, cid[n], q(n), brand, size, price, random.randint(8, 80)))
        sp += 1

out.append("COMMIT;")
import sys
sys.stderr.write("-- %d stores, %d store_products, %d canonicals\n" % (len(STORES), sp, len(CANON)))
print('\n'.join(out))
