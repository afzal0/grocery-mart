import uuid, random, subprocess, html
random.seed(42)

# Reuse existing canonicals so the new stores share comparable staples with Patel/Lahore.
EXIST = {
    "Aashirvaad Atta": ("f96d7135-1989-4274-aafc-20ba7c7bb6eb", "Aashirvaad", "5kg", "Flour", 19.50),
    "Toor Dal":        ("19d82c2c-0a7c-493a-9463-c845d35a416c", "TRS", "1kg", "Lentils", 4.20),
    "Paneer":          ("150c63d1-52da-4aad-9c6f-6ebd42411ffd", "Gopi", "200g", "Dairy", 5.00),
    "Basmati Rice":    ("082b5b67-3fc9-494a-8c61-b87f7a15791f", "Tilda", "5kg", "Rice", 21.00),
}

# New canonicals: name -> (brand, size, category, cuisine, base_price)
NEW = {
    "Sona Masoori Rice": ("India Gate","5kg","Rice","indian",16.50),
    "Idli Rice":         ("Laxmi","5kg","Rice","indian",17.90),
    "Chakki Atta":       ("Vimal","10kg","Flour","indian",24.00),
    "Moong Dal":         ("TRS","1kg","Lentils","indian",4.60),
    "Chana Dal":         ("TRS","1kg","Lentils","indian",4.10),
    "Masoor Dal":        ("TRS","1kg","Lentils","indian",3.80),
    "Urad Dal":          ("TRS","1kg","Lentils","indian",5.20),
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
    "Frozen Samosa":     ("Deep","12pk","Frozen","indian",6.50),
    "Frozen Paratha":    ("Kawan","5pk","Frozen","pakistani",5.40),
    "Okra (Bhindi)":     ("Fresh","500g","Vegetables","indian",4.00),
    "Curry Leaves":      ("Fresh","50g","Vegetables","srilankan",1.80),
    "Green Chilli":      ("Fresh","250g","Vegetables","indian",2.20),
    "Masala Chai":       ("Wagh Bakri","250g","Beverages","indian",5.60),
    "Rooh Afza":         ("Hamdard","750ml","Beverages","pakistani",6.80),
    "Coconut Milk":      ("Kara","400ml","Beverages","srilankan",2.10),
    "Kabuli Chana":      ("TRS","1kg","Lentils","afghan",4.90),
    "Vermicelli":        ("Bambino","400g","Snacks","pakistani",2.70),
}

CANON = {}  # name -> id
sql = ["BEGIN;"]

def mk(name, brand, size):
    key = ''.join(ch for ch in (brand+name+size).lower() if ch.isalnum())
    return key

# existing canonicals already in DB; just record their ids
for n,(cid,brand,size,cat,price) in EXIST.items():
    CANON[n] = cid

# insert new canonicals
for n,(brand,size,cat,cuisine,price) in NEW.items():
    cid = str(uuid.uuid4()); CANON[n]=cid
    key = mk(n,brand,size)
    sql.append("INSERT INTO canonical_product (id,name,brand,size_label,category,cuisine_tag,match_key) "
        "VALUES ('%s','%s','%s','%s','%s','%s','%s') ON CONFLICT (match_key) DO NOTHING;"%(
        cid, n.replace("'","''"), brand, size, cat, cuisine, key))

# product rating aggregates (display)
allnames = list(CANON.keys())
for n in allnames:
    cid = CANON[n]
    avg = round(random.uniform(3.9,4.9),1); cnt = random.randint(6,180)
    sql.append("INSERT INTO product_rating_aggregate (canonical_product_id,avg_rating,review_count) "
        "VALUES ('%s',%s,%d) ON CONFLICT (canonical_product_id) DO UPDATE SET avg_rating=EXCLUDED.avg_rating, review_count=EXCLUDED.review_count;"%(cid,avg,cnt))

# stores
NEW_STORES = [
    ("Spice Bazaar", ["indian"], "Harris Park, Sydney", -33.8230, 151.0040, "Family-run North & South Indian grocer."),
    ("Dhaka Grocers", ["bengali"], "Lakemba, Sydney", -33.9200, 151.0750, "Authentic Bangladeshi fish, rice & spices."),
    ("Colombo Market", ["srilankan"], "Homebush, Sydney", -33.8650, 151.0860, "Sri Lankan staples, coconut & curry leaves."),
    ("Kabul Foods", ["afghan","pakistani"], "Auburn, Sydney", -33.8490, 151.0330, "Afghan bread, dry fruits & halal goods."),
    ("Himalaya Mart", ["nepali","indian"], "Parramatta, Sydney", -33.8150, 151.0050, "Nepali & Indian pantry essentials."),
    ("Karachi Halal", ["pakistani"], "Granville, Sydney", -33.8330, 151.0120, "Pakistani spices, atta & frozen halal."),
    ("Madras Groceries", ["indian"], "Wentworthville, Sydney", -33.8070, 150.9720, "South Indian rice, dals & filter coffee."),
    ("Bengal Bazaar", ["bengali"], "Strathfield, Sydney", -33.8760, 151.0820, "Bengali sweets, mustard oil & fish."),
]

STAPLES = ["Aashirvaad Atta","Basmati Rice","Toor Dal","Pure Ghee"]  # common -> cross-store comparison
ALL = list(CANON.keys())

store_count = 0; sp_count = 0
# store rating aggregates for existing Patel/Lahore too
for pid in ["fc3f0296-c667-4deb-9eca-76364f68ad1c","84ac45fd-b92c-4437-ac88-da3d2b09f666"]:
    avg=round(random.uniform(4.2,4.8),1); cnt=random.randint(80,420)
    sql.append("INSERT INTO store_rating_aggregate (shop_id,avg_rating,review_count) VALUES ('%s',%s,%d) "
        "ON CONFLICT (shop_id) DO UPDATE SET avg_rating=EXCLUDED.avg_rating, review_count=EXCLUDED.review_count;"%(pid,avg,cnt))

for name, cuisines, addr, lat, lng, desc in NEW_STORES:
    oid = str(uuid.uuid4()); sid = str(uuid.uuid4())
    email = "owner_%s@grocery-mart.dev"%name.lower().replace(' ','').replace('&','')
    sql.append("INSERT INTO app_user (id,email,display_name,password_hash,status) VALUES "
        "('%s','%s','%s',crypt('shoppass123',gen_salt('bf')),'active') ON CONFLICT (email) DO NOTHING;"%(oid,email,name+" Owner"))
    sql.append("INSERT INTO user_role (user_id,role) VALUES ('%s','SHOP_OWNER') ON CONFLICT DO NOTHING;"%oid)
    tags = '{'+','.join(cuisines)+'}'
    sql.append("INSERT INTO shop (id,owner_id,name,cuisine_tags,status,description,address,is_open,location) VALUES "
        "('%s','%s','%s','%s','active','%s','%s',true,ST_SetSRID(ST_MakePoint(%s,%s),4326)::geography);"%(
        sid,oid,name.replace("'","''"),tags,desc.replace("'","''"),addr,lng,lat))
    avg=round(random.uniform(4.1,4.9),1); cnt=random.randint(24,360)
    sql.append("INSERT INTO store_rating_aggregate (shop_id,avg_rating,review_count) VALUES ('%s',%s,%d) "
        "ON CONFLICT (shop_id) DO UPDATE SET avg_rating=EXCLUDED.avg_rating, review_count=EXCLUDED.review_count;"%(sid,avg,cnt))
    store_count += 1
    # product selection: staples + cuisine-matched others
    pool = [n for n in NEW if NEW[n][3] in cuisines or NEW[n][3]=='indian']
    random.shuffle(pool)
    picks = STAPLES + pool[:random.randint(4,7)]
    seen=set()
    for n in picks:
        if n in seen: continue
        seen.add(n)
        cid = CANON[n]
        if n in EXIST: brand,size,base = EXIST[n][1],EXIST[n][2],EXIST[n][4]
        else: brand,size,base = NEW[n][0],NEW[n][1],NEW[n][4]
        price = round(base*random.uniform(0.88,1.22),2)
        stock = random.randint(8,80)
        sql.append("INSERT INTO store_product (shop_id,canonical_product_id,raw_name,raw_brand,raw_size,price_amount,currency,stock,match_status) "
            "VALUES ('%s','%s','%s','%s','%s',%s,'AUD',%d,'auto_linked');"%(sid,cid,n.replace("'","''"),brand,size,price,stock))
        sp_count += 1

sql.append("COMMIT;")
open('/tmp/seed.sql','w').write('\n'.join(sql))
print("generated: %d new stores, %d store_products, %d canonicals (%d new)"%(store_count,sp_count,len(CANON),len(NEW)))
