(function () {
  // Single source of truth for per-business-type dashboard labels, chart
  // copy, and default categories. Both ungani-presets.js (dashboard
  // labels/categories) and ungani-analytics.js (chart titles/copy) read
  // from this file instead of maintaining their own separate lists, so
  // every business type gets identical treatment everywhere it's used.
  //
  // Matching is fuzzy substring matching against the tenant's
  // business_type_key + business_type + business_name text, first match
  // in TYPES order wins. This intentionally keeps the existing
  // "one business type resolves to one config" behavior - merging
  // multiple selected sections together is a separate, later phase.

  const TYPES = [
  {
    "key": "logistics",
    "name": "Logistics & Transport",
    "match": [
      "logistics",
      "transport",
      "fleet",
      "trip",
      "trips",
      "cold chain",
      "reefer",
      "genset",
      "clearing",
      "forwarding"
    ],
    "dashboardTitle": "Logistics Operations Dashboard",
    "chartsTitle": "Logistics Analytics",
    "itemsLabel": "Fleet / Trips / Assets",
    "peopleLabel": "Drivers / Clients",
    "tasksLabel": "Trip Tasks / Follow-ups",
    "recordsLabel": "Operations Records",
    "calendarLabel": "Trips / Follow-ups",
    "documentsLabel": "Fleet / Client Documents",
    "incomeCategories": [
      "Transport Income",
      "Trip Payment",
      "Client Payment",
      "Clearing / Forwarding Fee",
      "Cold Chain Service Fee",
      "Equipment Hire Income",
      "Other Logistics Income"
    ],
    "expenseCategories": [
      "Fuel",
      "Driver Allowance",
      "Vehicle Maintenance",
      "Genset / Reefer Maintenance",
      "Toll / Parking",
      "Loading / Offloading",
      "Insurance",
      "Documentation",
      "Other Logistics Expense"
    ],
    "itemTypes": [
      "Truck",
      "Vehicle",
      "Genset",
      "Reefer",
      "Trip",
      "Container",
      "Asset",
      "Spare Part"
    ],
    "peopleTypes": [
      "Driver",
      "Client",
      "Customer",
      "Supplier",
      "Mechanic",
      "Supervisor",
      "Staff",
      "Contact"
    ],
    "taskTypes": [
      "Trip Follow-up",
      "Driver Follow-up",
      "Client Update",
      "Maintenance Reminder",
      "Document Collection",
      "Payment Reminder",
      "Delivery Confirmation"
    ],
    "recordTypes": [
      "Trip Update",
      "Fleet Update",
      "Driver Report",
      "Client Update",
      "Maintenance Record",
      "Fuel Record",
      "Incident Log"
    ],
    "documentTypes": [
      "Delivery Note",
      "Invoice",
      "Receipt",
      "Vehicle Document",
      "Insurance Document",
      "Client Agreement",
      "Trip Document"
    ],
    "calendarTypes": [
      "Trip Date",
      "Delivery Date",
      "Vehicle Service",
      "Client Meeting",
      "Payment Reminder",
      "Document Deadline"
    ],
    "pageTitle": "Logistics Operations Dashboard",
    "badge": "Logistics Workspace",
    "hero": "Track fleet, trips, drivers, assets, tasks, money records, documents, and support in one place.",
    "itemsTitle": "Fleet / Trips / Assets",
    "itemSingular": "Asset / Trip",
    "itemPlural": "Assets / Trips",
    "statusTitle": "Fleet / Asset Status",
    "progressTitle": "Trip / Work Progress",
    "peopleTitle": "Drivers / Clients",
    "peoplePrimary": "drivers",
    "peopleSecondary": "clients",
    "peoplePrimaryTypes": [
      "driver",
      "staff",
      "operator"
    ],
    "peopleSecondaryTypes": [
      "client",
      "customer",
      "lead"
    ],
    "pipelineTitle": "Client / Trip Pipeline",
    "topPerformerTitle": "Top Driver / Staff",
    "calendarTitle": "Trip / Follow-up Activity",
    "previewTitle": "Fleet / Trips Preview",
    "availableText": "available",
    "closedText": "completed"
  },
  {
    "key": "real_estate",
    "name": "Real Estate / Property Management",
    "match": [
      "real estate",
      "property",
      "properties",
      "housing",
      "land",
      "rental"
    ],
    "dashboardTitle": "Property Operations Dashboard",
    "chartsTitle": "Property Analytics",
    "itemsLabel": "Properties / Listings",
    "peopleLabel": "Agents / Leads",
    "tasksLabel": "Property Tasks / Follow-ups",
    "recordsLabel": "Property Records",
    "calendarLabel": "Viewings / Site Visits",
    "documentsLabel": "Property Documents",
    "incomeCategories": [
      "Property Sale",
      "Rental Income",
      "Booking Deposit",
      "Agency / Service Fee",
      "Management Fee",
      "Other Property Income"
    ],
    "expenseCategories": [
      "Agent Commission",
      "Marketing / Advertising",
      "Legal / Documentation Fees",
      "Property Maintenance",
      "Site Visit / Transport Cost",
      "Project Material Cost",
      "Staff Wages",
      "Other Real Estate Cost"
    ],
    "itemTypes": [
      "Apartment",
      "House",
      "Villa",
      "Land",
      "Commercial Unit",
      "Rental Unit",
      "Project / Development"
    ],
    "peopleTypes": [
      "Agent",
      "Lead",
      "Buyer",
      "Tenant",
      "Renter",
      "Investor",
      "Caretaker",
      "Contractor",
      "Client"
    ],
    "taskTypes": [
      "Lead Follow-up",
      "Viewing Schedule",
      "Document Collection",
      "Payment Reminder",
      "Agent Follow-up",
      "Maintenance Follow-up",
      "Project Update"
    ],
    "recordTypes": [
      "Lead Inquiry",
      "Viewing Note",
      "Sale Update",
      "Rental Update",
      "Project Update",
      "Maintenance Note",
      "Client Update"
    ],
    "documentTypes": [
      "Sale Agreement",
      "Lease Agreement",
      "Title Document",
      "Receipt",
      "Invoice",
      "Client ID",
      "Project Document"
    ],
    "calendarTypes": [
      "Viewing",
      "Site Visit",
      "Payment Reminder",
      "Document Deadline",
      "Client Meeting",
      "Agent Follow-up"
    ],
    "pageTitle": "Property Operations Dashboard",
    "badge": "Property Workspace",
    "hero": "Track properties, projects, agents, leads, viewings, tasks, money records, documents, and reports in one place.",
    "itemsTitle": "Properties / Listings",
    "itemSingular": "Property",
    "itemPlural": "Properties",
    "statusTitle": "Property Status",
    "progressTitle": "Project Progress",
    "peopleTitle": "Agents / Leads",
    "peoplePrimary": "agents",
    "peopleSecondary": "leads",
    "peoplePrimaryTypes": [
      "agent"
    ],
    "peopleSecondaryTypes": [
      "lead",
      "buyer",
      "renter",
      "tenant",
      "client"
    ],
    "pipelineTitle": "Lead Pipeline",
    "topPerformerTitle": "Top Agent This Month",
    "calendarTitle": "Viewings / Site Visits",
    "previewTitle": "Property Grid Preview",
    "availableText": "available",
    "closedText": "sold/rented"
  },
  {
    "key": "hospitality",
    "match": [
      "hospitality",
      "hotel",
      "restaurant",
      "bar and grill",
      "sports bar",
      "cocktail bar",
      "wine bar",
      "club",
      "venue",
      "lounge",
      "bnb",
      "guest house",
      "guesthouse",
      "lodge",
      "resort",
      "hostel",
      "airbnb"
    ],
    "pageTitle": "Hospitality Operations Dashboard",
    "chartsTitle": "Hospitality Analytics",
    "badge": "Hospitality Workspace",
    "hero": "Track rooms, tables, services, staff, bookings, tasks, money records, documents, and support in one place.",
    "itemsTitle": "Rooms / Tables / Services",
    "itemSingular": "Room / Service",
    "itemPlural": "Rooms / Services",
    "statusTitle": "Room / Service Status",
    "progressTitle": "Service / Booking Progress",
    "peopleTitle": "Staff / Guests",
    "peoplePrimary": "staff",
    "peopleSecondary": "guests",
    "peoplePrimaryTypes": [
      "staff",
      "manager",
      "waiter",
      "chef"
    ],
    "peopleSecondaryTypes": [
      "guest",
      "customer",
      "client",
      "lead"
    ],
    "pipelineTitle": "Guest / Booking Pipeline",
    "topPerformerTitle": "Top Staff Member",
    "calendarTitle": "Bookings / Reservations",
    "previewTitle": "Rooms / Services Preview",
    "availableText": "available",
    "closedText": "served",
    "name": "Hospitality / Restaurant / Venue",
    "dashboardTitle": "Hospitality Operations Dashboard",
    "itemsLabel": "Rooms / Tables / Menu Items",
    "peopleLabel": "Staff / Guests",
    "tasksLabel": "Booking / Service Tasks",
    "recordsLabel": "Guest / Service Records",
    "calendarLabel": "Bookings / Reservations",
    "documentsLabel": "Hospitality Documents",
    "incomeCategories": [
      "Room Booking Income",
      "Restaurant / Food Sales",
      "Bar / Beverage Sales",
      "Event / Function Income",
      "Service Charge",
      "Other Hospitality Income"
    ],
    "expenseCategories": [
      "Food & Beverage Supplies",
      "Staff Wages",
      "Utilities",
      "Laundry / Housekeeping",
      "Maintenance / Repairs",
      "Licensing",
      "Marketing / Advertising",
      "Other Hospitality Expense"
    ],
    "itemTypes": [
      "Room",
      "Table",
      "Menu Item",
      "Beverage",
      "Equipment",
      "Stock Item"
    ],
    "peopleTypes": [
      "Manager",
      "Waiter",
      "Chef",
      "Housekeeping Staff",
      "Staff",
      "Guest",
      "Customer",
      "Supplier"
    ],
    "taskTypes": [
      "Booking Follow-up",
      "Guest Request",
      "Housekeeping Task",
      "Maintenance Task",
      "Supplier Restock",
      "Payment Reminder"
    ],
    "recordTypes": [
      "Booking Update",
      "Guest Feedback",
      "Service Note",
      "Stock Update",
      "Daily Update",
      "Incident Log"
    ],
    "documentTypes": [
      "Receipt",
      "Invoice",
      "Booking Confirmation",
      "Guest ID",
      "Supplier Document",
      "License"
    ],
    "calendarTypes": [
      "Booking",
      "Reservation",
      "Event Date",
      "Staff Shift",
      "Payment Reminder"
    ]
  },
  {
    "key": "salon",
    "name": "Salon / Barber / Spa / Beauty",
    "match": [
      "salon",
      "barber",
      "spa",
      "beauty"
    ],
    "dashboardTitle": "Salon Operations Dashboard",
    "chartsTitle": "Salon Analytics",
    "itemsLabel": "Services / Products",
    "peopleLabel": "Staff / Clients",
    "tasksLabel": "Appointments / Follow-ups",
    "recordsLabel": "Client / Service Records",
    "calendarLabel": "Appointments",
    "documentsLabel": "Salon Documents",
    "incomeCategories": [
      "Service Income",
      "Product Sale",
      "Appointment Deposit",
      "Membership / Package",
      "Other Salon Income"
    ],
    "expenseCategories": [
      "Beauty Products",
      "Staff Wages",
      "Rent",
      "Utilities",
      "Equipment Maintenance",
      "Marketing / Advertising",
      "Other Salon Expense"
    ],
    "itemTypes": [
      "Service",
      "Product",
      "Equipment",
      "Package",
      "Appointment",
      "Stock Item"
    ],
    "peopleTypes": [
      "Stylist",
      "Barber",
      "Therapist",
      "Staff",
      "Client",
      "Customer",
      "Supplier"
    ],
    "taskTypes": [
      "Appointment Follow-up",
      "Client Reminder",
      "Product Restock",
      "Payment Follow-up",
      "Staff Task",
      "Cleaning Task"
    ],
    "recordTypes": [
      "Client Visit",
      "Service Note",
      "Product Sale",
      "Appointment Note",
      "Complaint / Feedback",
      "Daily Update"
    ],
    "documentTypes": [
      "Receipt",
      "Invoice",
      "Supplier Document",
      "Staff Document",
      "Business Document"
    ],
    "calendarTypes": [
      "Appointment",
      "Client Follow-up",
      "Staff Shift",
      "Product Restock",
      "Payment Reminder"
    ],
    "pageTitle": "Salon Operations Dashboard",
    "badge": "Salon Workspace",
    "hero": "Track services, appointments, staff, clients, products, tasks, money records, and support in one place.",
    "itemsTitle": "Services / Products",
    "itemSingular": "Service / Product",
    "itemPlural": "Services / Products",
    "statusTitle": "Service / Product Status",
    "progressTitle": "Appointment / Work Progress",
    "peopleTitle": "Staff / Clients",
    "peoplePrimary": "staff",
    "peopleSecondary": "clients",
    "peoplePrimaryTypes": [
      "staff",
      "stylist",
      "barber",
      "therapist"
    ],
    "peopleSecondaryTypes": [
      "client",
      "customer",
      "lead"
    ],
    "pipelineTitle": "Client Pipeline",
    "topPerformerTitle": "Top Staff Member",
    "calendarTitle": "Appointments",
    "previewTitle": "Services / Products Preview",
    "availableText": "available",
    "closedText": "completed"
  },
  {
    "key": "car_wash",
    "name": "Car Wash / Auto Detailing",
    "match": [
      "car wash",
      "auto detailing",
      "detailing"
    ],
    "dashboardTitle": "Car Wash Operations Dashboard",
    "chartsTitle": "Car Wash Analytics",
    "itemsLabel": "Services / Equipment",
    "peopleLabel": "Staff / Customers",
    "tasksLabel": "Bookings / Service Tasks",
    "recordsLabel": "Service Records",
    "calendarLabel": "Bookings / Services",
    "documentsLabel": "Car Wash Documents",
    "incomeCategories": [
      "Car Wash Service",
      "Detailing Service",
      "Customer Payment",
      "Package Payment",
      "Other Car Wash Income"
    ],
    "expenseCategories": [
      "Cleaning Supplies",
      "Water",
      "Electricity",
      "Staff Wages",
      "Equipment Maintenance",
      "Marketing / Advertising",
      "Other Car Wash Expense"
    ],
    "itemTypes": [
      "Service",
      "Equipment",
      "Cleaning Product",
      "Package",
      "Booking"
    ],
    "peopleTypes": [
      "Washer",
      "Detailer",
      "Manager",
      "Staff",
      "Customer",
      "Supplier"
    ],
    "taskTypes": [
      "Customer Booking",
      "Service Follow-up",
      "Equipment Maintenance",
      "Product Restock",
      "Payment Follow-up",
      "Cleaning Task"
    ],
    "recordTypes": [
      "Service Record",
      "Customer Feedback",
      "Daily Sales Note",
      "Equipment Note",
      "Incident Log"
    ],
    "documentTypes": [
      "Receipt",
      "Invoice",
      "Supplier Document",
      "Equipment Document",
      "Business Document"
    ],
    "calendarTypes": [
      "Booking",
      "Service Appointment",
      "Equipment Service",
      "Customer Follow-up",
      "Payment Reminder"
    ],
    "pageTitle": "Car Wash Operations Dashboard",
    "badge": "Car Wash Workspace",
    "hero": "Track services, bookings, customers, staff, equipment, money records, tasks, and support in one place.",
    "itemsTitle": "Services / Equipment",
    "itemSingular": "Service / Equipment",
    "itemPlural": "Services / Equipment",
    "statusTitle": "Service / Equipment Status",
    "progressTitle": "Booking / Service Progress",
    "peopleTitle": "Staff / Customers",
    "peoplePrimary": "staff",
    "peopleSecondary": "customers",
    "peoplePrimaryTypes": [
      "staff",
      "washer",
      "detailer",
      "manager"
    ],
    "peopleSecondaryTypes": [
      "customer",
      "client",
      "lead"
    ],
    "pipelineTitle": "Customer Pipeline",
    "topPerformerTitle": "Top Staff Member",
    "calendarTitle": "Bookings / Services",
    "previewTitle": "Services / Equipment Preview",
    "availableText": "available",
    "closedText": "completed"
  },
  {
    "key": "printing",
    "name": "Printing / Branding Company",
    "match": [
      "printing",
      "branding",
      "print",
      "design"
    ],
    "dashboardTitle": "Printing Operations Dashboard",
    "chartsTitle": "Printing Analytics",
    "itemsLabel": "Jobs / Orders / Materials",
    "peopleLabel": "Staff / Clients",
    "tasksLabel": "Print Job Tasks",
    "recordsLabel": "Job Records",
    "calendarLabel": "Jobs / Delivery Dates",
    "documentsLabel": "Job Documents",
    "incomeCategories": [
      "Print Job Payment",
      "Branding Job Payment",
      "Design Fee",
      "Deposit",
      "Delivery Fee",
      "Other Printing Income"
    ],
    "expenseCategories": [
      "Printing Materials",
      "Ink / Toner",
      "Paper / Media",
      "Machine Maintenance",
      "Staff Wages",
      "Transport / Delivery",
      "Other Printing Expense"
    ],
    "itemTypes": [
      "Print Job",
      "Branding Job",
      "Material",
      "Machine",
      "Design Project",
      "Order"
    ],
    "peopleTypes": [
      "Designer",
      "Printer",
      "Staff",
      "Client",
      "Customer",
      "Supplier"
    ],
    "taskTypes": [
      "Design Task",
      "Print Task",
      "Client Approval",
      "Delivery Follow-up",
      "Payment Reminder",
      "Material Restock"
    ],
    "recordTypes": [
      "Job Update",
      "Client Approval",
      "Design Note",
      "Print Note",
      "Delivery Note",
      "Complaint / Revision"
    ],
    "documentTypes": [
      "Quotation",
      "Invoice",
      "Receipt",
      "Artwork File",
      "Client Approval",
      "Delivery Note"
    ],
    "calendarTypes": [
      "Job Deadline",
      "Delivery Date",
      "Client Approval Date",
      "Payment Reminder",
      "Material Restock"
    ],
    "pageTitle": "Printing Operations Dashboard",
    "badge": "Printing Workspace",
    "hero": "Track print jobs, orders, materials, clients, staff, money records, tasks, and delivery follow-ups in one place.",
    "itemsTitle": "Jobs / Orders / Materials",
    "itemSingular": "Job / Material",
    "itemPlural": "Jobs / Materials",
    "statusTitle": "Job / Material Status",
    "progressTitle": "Job Progress",
    "peopleTitle": "Staff / Clients",
    "peoplePrimary": "staff",
    "peopleSecondary": "clients",
    "peoplePrimaryTypes": [
      "staff",
      "designer",
      "printer",
      "manager"
    ],
    "peopleSecondaryTypes": [
      "client",
      "customer",
      "lead"
    ],
    "pipelineTitle": "Order Pipeline",
    "topPerformerTitle": "Top Staff Member",
    "calendarTitle": "Jobs / Delivery Dates",
    "previewTitle": "Jobs / Materials Preview",
    "availableText": "available",
    "closedText": "completed"
  },
  {
    "key": "boutique",
    "match": [
      "boutique",
      "fashion",
      "clothing",
      "apparel"
    ],
    "pageTitle": "Boutique Operations Dashboard",
    "chartsTitle": "Boutique Analytics",
    "badge": "Retail Fashion Workspace",
    "hero": "Track stock, sales, customers, suppliers, staff, money records, tasks, and support in one place.",
    "itemsTitle": "Stock / Products",
    "itemSingular": "Product",
    "itemPlural": "Products",
    "statusTitle": "Stock Status",
    "progressTitle": "Stock / Sales Progress",
    "peopleTitle": "Staff / Customers",
    "peoplePrimary": "staff",
    "peopleSecondary": "customers",
    "peoplePrimaryTypes": [
      "staff",
      "manager",
      "sales"
    ],
    "peopleSecondaryTypes": [
      "customer",
      "client",
      "supplier",
      "lead"
    ],
    "pipelineTitle": "Customer / Sales Pipeline",
    "topPerformerTitle": "Top Sales Staff",
    "calendarTitle": "Sales / Restock Activity",
    "previewTitle": "Stock / Products Preview",
    "availableText": "in stock",
    "closedText": "sold",
    "name": "Boutique / Fashion Retail",
    "dashboardTitle": "Boutique Operations Dashboard",
    "itemsLabel": "Stock / Fashion Items",
    "peopleLabel": "Staff / Customers",
    "tasksLabel": "Stock / Sales Tasks",
    "recordsLabel": "Sales / Stock Records",
    "calendarLabel": "Sales / Restock Activity",
    "documentsLabel": "Boutique Documents",
    "incomeCategories": [
      "Product Sale",
      "Customer Payment",
      "Bulk Sale",
      "Online Sale",
      "Other Boutique Income"
    ],
    "expenseCategories": [
      "Stock Purchase",
      "Supplier Payment",
      "Staff Wages",
      "Rent",
      "Packaging",
      "Marketing / Advertising",
      "Other Boutique Expense"
    ],
    "itemTypes": [
      "Clothing Item",
      "Accessory",
      "Footwear",
      "Stock Item",
      "Bundle"
    ],
    "peopleTypes": [
      "Staff",
      "Customer",
      "Supplier",
      "Manager",
      "Sales Person",
      "Lead"
    ],
    "taskTypes": [
      "Restock Reminder",
      "Supplier Follow-up",
      "Customer Follow-up",
      "Payment Reminder",
      "Stock Count"
    ],
    "recordTypes": [
      "Sales Note",
      "Stock Update",
      "Supplier Update",
      "Customer Request",
      "Daily Update"
    ],
    "documentTypes": [
      "Receipt",
      "Invoice",
      "Supplier Invoice",
      "Stock List",
      "Business Document"
    ],
    "calendarTypes": [
      "Restock Date",
      "Supplier Follow-up",
      "Delivery Date",
      "Payment Reminder",
      "Stock Count"
    ]
  },
  {
    "key": "retail",
    "name": "Retail Shop / Mini Market",
    "match": [
      "retail",
      "mini market",
      "shop",
      "store"
    ],
    "dashboardTitle": "Retail Operations Dashboard",
    "chartsTitle": "Retail Analytics",
    "itemsLabel": "Stock / Products",
    "peopleLabel": "Staff / Customers",
    "tasksLabel": "Stock / Sales Tasks",
    "recordsLabel": "Sales / Stock Records",
    "calendarLabel": "Sales / Restock Activity",
    "documentsLabel": "Retail Documents",
    "incomeCategories": [
      "Product Sale",
      "Customer Payment",
      "Bulk Sale",
      "Online Sale",
      "Other Retail Income"
    ],
    "expenseCategories": [
      "Stock Purchase",
      "Supplier Payment",
      "Staff Wages",
      "Rent",
      "Transport",
      "Packaging",
      "Marketing / Advertising",
      "Other Retail Expense"
    ],
    "itemTypes": [
      "Product",
      "Stock Item",
      "Asset",
      "Supplier Item",
      "Bundle"
    ],
    "peopleTypes": [
      "Staff",
      "Customer",
      "Supplier",
      "Manager",
      "Sales Person",
      "Lead"
    ],
    "taskTypes": [
      "Restock Reminder",
      "Supplier Follow-up",
      "Customer Follow-up",
      "Payment Reminder",
      "Stock Count",
      "Delivery Follow-up"
    ],
    "recordTypes": [
      "Sales Note",
      "Stock Update",
      "Supplier Update",
      "Customer Request",
      "Daily Update",
      "Damaged Stock"
    ],
    "documentTypes": [
      "Receipt",
      "Invoice",
      "Supplier Invoice",
      "Stock List",
      "Delivery Note",
      "Business Document"
    ],
    "calendarTypes": [
      "Restock Date",
      "Supplier Follow-up",
      "Delivery Date",
      "Payment Reminder",
      "Stock Count"
    ],
    "pageTitle": "Retail Operations Dashboard",
    "badge": "Retail Workspace",
    "hero": "Track stock, sales, suppliers, customers, staff, money records, tasks, and support in one place.",
    "itemsTitle": "Stock / Products",
    "itemSingular": "Product",
    "itemPlural": "Products",
    "statusTitle": "Stock Status",
    "progressTitle": "Stock / Sales Progress",
    "peopleTitle": "Staff / Customers",
    "peoplePrimary": "staff",
    "peopleSecondary": "customers",
    "peoplePrimaryTypes": [
      "staff",
      "manager",
      "sales"
    ],
    "peopleSecondaryTypes": [
      "customer",
      "client",
      "supplier",
      "lead"
    ],
    "pipelineTitle": "Customer / Sales Pipeline",
    "topPerformerTitle": "Top Sales Staff",
    "calendarTitle": "Sales / Restock Activity",
    "previewTitle": "Stock / Products Preview",
    "availableText": "in stock",
    "closedText": "sold"
  },
  {
    "key": "pharmacy",
    "name": "Pharmacy",
    "match": [
      "pharmacy",
      "chemist",
      "medicine"
    ],
    "dashboardTitle": "Pharmacy Operations Dashboard",
    "chartsTitle": "Pharmacy Analytics",
    "itemsLabel": "Medicines / Stock",
    "peopleLabel": "Staff / Suppliers",
    "tasksLabel": "Pharmacy Tasks",
    "recordsLabel": "Stock / Sales Records",
    "calendarLabel": "Restock / Follow-ups",
    "documentsLabel": "Pharmacy Documents",
    "incomeCategories": [
      "Medicine Sale",
      "Customer Payment",
      "Prescription Sale",
      "Other Pharmacy Income"
    ],
    "expenseCategories": [
      "Medicine Purchase",
      "Supplier Payment",
      "Staff Wages",
      "Rent",
      "Utilities",
      "Licensing",
      "Expired Stock Loss",
      "Other Pharmacy Expense"
    ],
    "itemTypes": [
      "Medicine",
      "Medical Supply",
      "Stock Item",
      "Equipment",
      "Supplier Item"
    ],
    "peopleTypes": [
      "Pharmacist",
      "Staff",
      "Supplier",
      "Customer",
      "Doctor / Referral",
      "Manager"
    ],
    "taskTypes": [
      "Restock Reminder",
      "Expiry Check",
      "Supplier Follow-up",
      "Payment Reminder",
      "Stock Count",
      "Customer Follow-up"
    ],
    "recordTypes": [
      "Stock Update",
      "Sales Note",
      "Expired Stock",
      "Supplier Update",
      "Customer Request",
      "Daily Update"
    ],
    "documentTypes": [
      "Receipt",
      "Invoice",
      "Supplier Invoice",
      "License",
      "Stock List",
      "Business Document"
    ],
    "calendarTypes": [
      "Restock Date",
      "Expiry Check",
      "Supplier Follow-up",
      "Payment Reminder",
      "Stock Count"
    ],
    "pageTitle": "Pharmacy Operations Dashboard",
    "badge": "Pharmacy Workspace",
    "hero": "Track medicines, stock, suppliers, customers, staff, money records, tasks, and support in one place.",
    "itemsTitle": "Medicines / Stock",
    "itemSingular": "Medicine / Stock",
    "itemPlural": "Medicines / Stock",
    "statusTitle": "Medicine / Stock Status",
    "progressTitle": "Stock / Restock Progress",
    "peopleTitle": "Staff / Suppliers",
    "peoplePrimary": "staff",
    "peopleSecondary": "suppliers",
    "peoplePrimaryTypes": [
      "staff",
      "pharmacist",
      "manager"
    ],
    "peopleSecondaryTypes": [
      "supplier",
      "customer",
      "client",
      "lead"
    ],
    "pipelineTitle": "Supplier / Customer Pipeline",
    "topPerformerTitle": "Top Staff Member",
    "calendarTitle": "Restock / Follow-ups",
    "previewTitle": "Medicines / Stock Preview",
    "availableText": "in stock",
    "closedText": "sold"
  },
  {
    "key": "gym",
    "name": "Gym / Fitness Center",
    "match": [
      "gym",
      "fitness",
      "wellness"
    ],
    "dashboardTitle": "Gym Operations Dashboard",
    "chartsTitle": "Gym Analytics",
    "itemsLabel": "Services / Equipment",
    "peopleLabel": "Trainers / Members",
    "tasksLabel": "Membership / Service Tasks",
    "recordsLabel": "Member / Service Records",
    "calendarLabel": "Sessions / Renewals",
    "documentsLabel": "Gym Documents",
    "incomeCategories": [
      "Membership Payment",
      "Training Session Fee",
      "Package Payment",
      "Product Sale",
      "Other Gym Income"
    ],
    "expenseCategories": [
      "Trainer Payment",
      "Equipment Maintenance",
      "Rent",
      "Utilities",
      "Cleaning",
      "Marketing / Advertising",
      "Other Gym Expense"
    ],
    "itemTypes": [
      "Membership Package",
      "Training Service",
      "Equipment",
      "Product",
      "Class"
    ],
    "peopleTypes": [
      "Trainer",
      "Staff",
      "Member",
      "Client",
      "Customer",
      "Supplier"
    ],
    "taskTypes": [
      "Membership Renewal",
      "Client Follow-up",
      "Training Session",
      "Equipment Maintenance",
      "Payment Reminder",
      "Class Schedule"
    ],
    "recordTypes": [
      "Member Update",
      "Training Note",
      "Payment Note",
      "Equipment Note",
      "Daily Update"
    ],
    "documentTypes": [
      "Membership Form",
      "Receipt",
      "Invoice",
      "Staff Document",
      "Business Document"
    ],
    "calendarTypes": [
      "Training Session",
      "Membership Renewal",
      "Class",
      "Payment Reminder",
      "Equipment Service"
    ],
    "pageTitle": "Gym Operations Dashboard",
    "badge": "Fitness Workspace",
    "hero": "Track memberships, services, trainers, clients, equipment, money records, tasks, and support in one place.",
    "itemsTitle": "Services / Equipment",
    "itemSingular": "Service / Equipment",
    "itemPlural": "Services / Equipment",
    "statusTitle": "Service / Equipment Status",
    "progressTitle": "Membership / Service Progress",
    "peopleTitle": "Trainers / Members",
    "peoplePrimary": "trainers",
    "peopleSecondary": "members",
    "peoplePrimaryTypes": [
      "trainer",
      "staff",
      "manager"
    ],
    "peopleSecondaryTypes": [
      "member",
      "client",
      "customer",
      "lead"
    ],
    "pipelineTitle": "Member Pipeline",
    "topPerformerTitle": "Top Trainer / Staff",
    "calendarTitle": "Sessions / Renewals",
    "previewTitle": "Services / Equipment Preview",
    "availableText": "available",
    "closedText": "completed"
  },
  {
    "key": "warehouse",
    "name": "Warehouse & Storage",
    "match": [
      "warehouse",
      "storage"
    ],
    "dashboardTitle": "Warehouse Operations Dashboard",
    "chartsTitle": "Warehouse Analytics",
    "itemsLabel": "Storage / Stock / Assets",
    "peopleLabel": "Staff / Clients",
    "tasksLabel": "Warehouse Tasks",
    "recordsLabel": "Storage / Stock Records",
    "calendarLabel": "Dispatch / Storage Activity",
    "documentsLabel": "Warehouse Documents",
    "incomeCategories": [
      "Storage Fee",
      "Handling Fee",
      "Client Payment",
      "Dispatch Fee",
      "Other Warehouse Income"
    ],
    "expenseCategories": [
      "Staff Wages",
      "Equipment Maintenance",
      "Rent",
      "Utilities",
      "Security",
      "Transport",
      "Other Warehouse Expense"
    ],
    "itemTypes": [
      "Stock Item",
      "Storage Unit",
      "Pallet",
      "Asset",
      "Equipment",
      "Dispatch"
    ],
    "peopleTypes": [
      "Warehouse Staff",
      "Manager",
      "Client",
      "Customer",
      "Supplier",
      "Driver"
    ],
    "taskTypes": [
      "Stock Count",
      "Dispatch Follow-up",
      "Client Update",
      "Equipment Maintenance",
      "Payment Reminder",
      "Receiving Task"
    ],
    "recordTypes": [
      "Stock Update",
      "Dispatch Note",
      "Receiving Note",
      "Client Update",
      "Damage Report",
      "Daily Update"
    ],
    "documentTypes": [
      "Delivery Note",
      "Stock Sheet",
      "Invoice",
      "Receipt",
      "Client Agreement",
      "Warehouse Document"
    ],
    "calendarTypes": [
      "Dispatch Date",
      "Receiving Date",
      "Stock Count",
      "Client Follow-up",
      "Payment Reminder"
    ],
    "pageTitle": "Warehouse Operations Dashboard",
    "badge": "Warehouse Workspace",
    "hero": "Track storage units, stock, clients, staff, tasks, money records, documents, and support in one place.",
    "itemsTitle": "Storage / Stock / Assets",
    "itemSingular": "Storage / Stock",
    "itemPlural": "Storage / Stock",
    "statusTitle": "Storage / Stock Status",
    "progressTitle": "Storage / Work Progress",
    "peopleTitle": "Staff / Clients",
    "peoplePrimary": "staff",
    "peopleSecondary": "clients",
    "peoplePrimaryTypes": [
      "staff",
      "manager",
      "operator"
    ],
    "peopleSecondaryTypes": [
      "client",
      "customer",
      "supplier",
      "lead"
    ],
    "pipelineTitle": "Client / Storage Pipeline",
    "topPerformerTitle": "Top Staff Member",
    "calendarTitle": "Dispatch / Storage Activity",
    "previewTitle": "Storage / Stock Preview",
    "availableText": "available",
    "closedText": "completed"
  },
  {
    "key": "security",
    "name": "Security / Guarding Company",
    "match": [
      "security",
      "guarding",
      "guards"
    ],
    "dashboardTitle": "Security Operations Dashboard",
    "chartsTitle": "Security Analytics",
    "itemsLabel": "Sites / Shifts / Equipment",
    "peopleLabel": "Guards / Clients",
    "tasksLabel": "Security Tasks",
    "recordsLabel": "Site / Shift Records",
    "calendarLabel": "Shifts / Site Visits",
    "documentsLabel": "Security Documents",
    "incomeCategories": [
      "Client Payment",
      "Security Service Fee",
      "Contract Payment",
      "Other Security Income"
    ],
    "expenseCategories": [
      "Guard Wages",
      "Uniforms",
      "Transport",
      "Equipment",
      "Training",
      "Communication",
      "Other Security Expense"
    ],
    "itemTypes": [
      "Site",
      "Shift",
      "Equipment",
      "Uniform",
      "Patrol Record"
    ],
    "peopleTypes": [
      "Guard",
      "Supervisor",
      "Manager",
      "Client",
      "Customer",
      "Staff"
    ],
    "taskTypes": [
      "Shift Assignment",
      "Site Follow-up",
      "Incident Follow-up",
      "Client Update",
      "Payment Reminder",
      "Equipment Check"
    ],
    "recordTypes": [
      "Shift Report",
      "Incident Report",
      "Site Update",
      "Client Update",
      "Attendance Record",
      "Daily Update"
    ],
    "documentTypes": [
      "Contract",
      "Invoice",
      "Receipt",
      "Guard Document",
      "Incident Report",
      "Client Document"
    ],
    "calendarTypes": [
      "Shift",
      "Site Visit",
      "Client Meeting",
      "Payment Reminder",
      "Training"
    ],
    "pageTitle": "Security Operations Dashboard",
    "badge": "Security Workspace",
    "hero": "Track guards, sites, shifts, clients, tasks, money records, documents, and support in one place.",
    "itemsTitle": "Sites / Shifts / Equipment",
    "itemSingular": "Site / Shift",
    "itemPlural": "Sites / Shifts",
    "statusTitle": "Site / Shift Status",
    "progressTitle": "Shift / Work Progress",
    "peopleTitle": "Guards / Clients",
    "peoplePrimary": "guards",
    "peopleSecondary": "clients",
    "peoplePrimaryTypes": [
      "guard",
      "staff",
      "supervisor",
      "manager"
    ],
    "peopleSecondaryTypes": [
      "client",
      "customer",
      "lead"
    ],
    "pipelineTitle": "Client / Site Pipeline",
    "topPerformerTitle": "Top Guard / Staff",
    "calendarTitle": "Shifts / Site Visits",
    "previewTitle": "Sites / Shifts Preview",
    "availableText": "active",
    "closedText": "completed"
  },
  {
    "key": "cleaning",
    "name": "Cleaning / Facility Services",
    "match": [
      "cleaning",
      "facility",
      "facilities"
    ],
    "dashboardTitle": "Cleaning Operations Dashboard",
    "chartsTitle": "Cleaning Analytics",
    "itemsLabel": "Jobs / Sites / Supplies",
    "peopleLabel": "Staff / Clients",
    "tasksLabel": "Cleaning Tasks",
    "recordsLabel": "Job / Site Records",
    "calendarLabel": "Cleaning Schedule",
    "documentsLabel": "Cleaning Documents",
    "incomeCategories": [
      "Cleaning Service Fee",
      "Client Payment",
      "Contract Payment",
      "Other Cleaning Income"
    ],
    "expenseCategories": [
      "Cleaning Supplies",
      "Staff Wages",
      "Transport",
      "Equipment Maintenance",
      "Uniforms",
      "Other Cleaning Expense"
    ],
    "itemTypes": [
      "Cleaning Job",
      "Site",
      "Supply",
      "Equipment",
      "Contract"
    ],
    "peopleTypes": [
      "Cleaner",
      "Supervisor",
      "Staff",
      "Client",
      "Customer",
      "Supplier"
    ],
    "taskTypes": [
      "Cleaning Job",
      "Site Follow-up",
      "Supply Restock",
      "Client Update",
      "Payment Reminder",
      "Equipment Check"
    ],
    "recordTypes": [
      "Job Update",
      "Site Report",
      "Client Feedback",
      "Supply Note",
      "Daily Update",
      "Issue Log"
    ],
    "documentTypes": [
      "Contract",
      "Invoice",
      "Receipt",
      "Client Document",
      "Staff Document"
    ],
    "calendarTypes": [
      "Cleaning Schedule",
      "Site Visit",
      "Client Follow-up",
      "Payment Reminder",
      "Supply Restock"
    ],
    "pageTitle": "Cleaning Operations Dashboard",
    "badge": "Cleaning Workspace",
    "hero": "Track cleaning jobs, sites, staff, clients, supplies, money records, tasks, and support in one place.",
    "itemsTitle": "Jobs / Sites / Supplies",
    "itemSingular": "Job / Site",
    "itemPlural": "Jobs / Sites",
    "statusTitle": "Job / Site Status",
    "progressTitle": "Cleaning Job Progress",
    "peopleTitle": "Staff / Clients",
    "peoplePrimary": "staff",
    "peopleSecondary": "clients",
    "peoplePrimaryTypes": [
      "staff",
      "cleaner",
      "supervisor",
      "manager"
    ],
    "peopleSecondaryTypes": [
      "client",
      "customer",
      "lead"
    ],
    "pipelineTitle": "Client / Job Pipeline",
    "topPerformerTitle": "Top Staff Member",
    "calendarTitle": "Cleaning Schedule",
    "previewTitle": "Jobs / Sites Preview",
    "availableText": "active",
    "closedText": "completed"
  },
  {
    "key": "construction",
    "name": "Construction / Contractors",
    "match": [
      "construction",
      "contractor",
      "contractors",
      "building"
    ],
    "dashboardTitle": "Construction Operations Dashboard",
    "chartsTitle": "Construction Analytics",
    "itemsLabel": "Projects / Materials / Assets",
    "peopleLabel": "Workers / Clients",
    "tasksLabel": "Construction Tasks",
    "recordsLabel": "Project Records",
    "calendarLabel": "Project Schedule",
    "documentsLabel": "Construction Documents",
    "incomeCategories": [
      "Project Payment",
      "Client Deposit",
      "Contract Payment",
      "Service Fee",
      "Other Construction Income"
    ],
    "expenseCategories": [
      "Materials",
      "Labour",
      "Transport",
      "Equipment Hire",
      "Subcontractor Payment",
      "Site Expenses",
      "Other Construction Expense"
    ],
    "itemTypes": [
      "Project",
      "Material",
      "Asset",
      "Equipment",
      "Site",
      "Work Package"
    ],
    "peopleTypes": [
      "Worker",
      "Contractor",
      "Supplier",
      "Client",
      "Engineer",
      "Supervisor",
      "Staff"
    ],
    "taskTypes": [
      "Project Task",
      "Material Follow-up",
      "Site Update",
      "Client Update",
      "Payment Reminder",
      "Inspection"
    ],
    "recordTypes": [
      "Project Update",
      "Site Report",
      "Material Record",
      "Client Update",
      "Issue Log",
      "Daily Update"
    ],
    "documentTypes": [
      "Contract",
      "Quotation",
      "Invoice",
      "Receipt",
      "Project Document",
      "Site Document"
    ],
    "calendarTypes": [
      "Site Visit",
      "Inspection",
      "Project Deadline",
      "Material Delivery",
      "Payment Reminder"
    ],
    "pageTitle": "Construction Operations Dashboard",
    "badge": "Construction Workspace",
    "hero": "Track projects, materials, workers, contractors, clients, tasks, money records, documents, and support in one place.",
    "itemsTitle": "Projects / Materials / Assets",
    "itemSingular": "Project / Material",
    "itemPlural": "Projects / Materials",
    "statusTitle": "Project / Material Status",
    "progressTitle": "Project Progress",
    "peopleTitle": "Workers / Clients",
    "peoplePrimary": "workers",
    "peopleSecondary": "clients",
    "peoplePrimaryTypes": [
      "worker",
      "staff",
      "contractor",
      "manager"
    ],
    "peopleSecondaryTypes": [
      "client",
      "customer",
      "supplier",
      "lead"
    ],
    "pipelineTitle": "Project / Client Pipeline",
    "topPerformerTitle": "Top Worker / Staff",
    "calendarTitle": "Project Schedule",
    "previewTitle": "Projects / Materials Preview",
    "availableText": "available",
    "closedText": "completed"
  },
  {
    "key": "clinic",
    "name": "Clinic / Health Services",
    "match": [
      "clinic",
      "health",
      "medical",
      "hospital"
    ],
    "dashboardTitle": "Clinic Operations Dashboard",
    "chartsTitle": "Clinic Analytics",
    "itemsLabel": "Supplies / Equipment",
    "peopleLabel": "Staff / Patients",
    "tasksLabel": "Clinic Tasks",
    "recordsLabel": "Patient / Clinic Records",
    "calendarLabel": "Appointments",
    "documentsLabel": "Clinic Documents",
    "incomeCategories": [
      "Consultation Fee",
      "Service Payment",
      "Medicine Sale",
      "Client Payment",
      "Other Clinic Income"
    ],
    "expenseCategories": [
      "Medical Supplies",
      "Staff Wages",
      "Rent",
      "Utilities",
      "Equipment Maintenance",
      "Licensing",
      "Other Clinic Expense"
    ],
    "itemTypes": [
      "Medical Supply",
      "Equipment",
      "Service",
      "Medicine",
      "Asset"
    ],
    "peopleTypes": [
      "Doctor",
      "Nurse",
      "Staff",
      "Patient",
      "Client",
      "Supplier"
    ],
    "taskTypes": [
      "Patient Follow-up",
      "Appointment",
      "Supply Restock",
      "Payment Reminder",
      "Equipment Maintenance",
      "Document Follow-up"
    ],
    "recordTypes": [
      "Patient Visit",
      "Clinic Note",
      "Payment Note",
      "Supply Update",
      "Daily Update",
      "Issue Log"
    ],
    "documentTypes": [
      "Receipt",
      "Invoice",
      "Patient Document",
      "Staff Document",
      "License",
      "Business Document"
    ],
    "calendarTypes": [
      "Appointment",
      "Patient Follow-up",
      "Supply Restock",
      "Payment Reminder",
      "Equipment Service"
    ],
    "pageTitle": "Clinic Operations Dashboard",
    "badge": "Health Services Workspace",
    "hero": "Track appointments, patients, staff, supplies, tasks, money records, documents, and support in one place.",
    "itemsTitle": "Supplies / Equipment",
    "itemSingular": "Supply / Equipment",
    "itemPlural": "Supplies / Equipment",
    "statusTitle": "Supply / Equipment Status",
    "progressTitle": "Appointment / Work Progress",
    "peopleTitle": "Staff / Patients",
    "peoplePrimary": "staff",
    "peopleSecondary": "patients",
    "peoplePrimaryTypes": [
      "staff",
      "doctor",
      "nurse",
      "manager"
    ],
    "peopleSecondaryTypes": [
      "patient",
      "client",
      "customer",
      "lead"
    ],
    "pipelineTitle": "Patient Pipeline",
    "topPerformerTitle": "Top Staff Member",
    "calendarTitle": "Appointments",
    "previewTitle": "Supplies / Equipment Preview",
    "availableText": "available",
    "closedText": "completed"
  },
  {
    "key": "school",
    "name": "School / Training Center",
    "match": [
      "school",
      "training",
      "academy",
      "education"
    ],
    "dashboardTitle": "School Operations Dashboard",
    "chartsTitle": "School Analytics",
    "itemsLabel": "Classes / Assets / Materials",
    "peopleLabel": "Staff / Learners",
    "tasksLabel": "School Tasks",
    "recordsLabel": "Learner / School Records",
    "calendarLabel": "Classes / Training",
    "documentsLabel": "School Documents",
    "incomeCategories": [
      "School Fees",
      "Training Fee",
      "Registration Fee",
      "Material Fee",
      "Other School Income"
    ],
    "expenseCategories": [
      "Staff Wages",
      "Learning Materials",
      "Rent",
      "Utilities",
      "Transport",
      "Equipment",
      "Other School Expense"
    ],
    "itemTypes": [
      "Class",
      "Course",
      "Asset",
      "Learning Material",
      "Equipment"
    ],
    "peopleTypes": [
      "Teacher",
      "Trainer",
      "Staff",
      "Learner",
      "Student",
      "Parent",
      "Supplier"
    ],
    "taskTypes": [
      "Learner Follow-up",
      "Fee Reminder",
      "Class Task",
      "Document Collection",
      "Parent Follow-up",
      "Training Task"
    ],
    "recordTypes": [
      "Learner Update",
      "Class Update",
      "Fee Note",
      "Parent Update",
      "Daily Update",
      "Issue Log"
    ],
    "documentTypes": [
      "Receipt",
      "Invoice",
      "Learner Document",
      "Staff Document",
      "Training Material",
      "Business Document"
    ],
    "calendarTypes": [
      "Class",
      "Training Session",
      "Fee Reminder",
      "Parent Meeting",
      "Exam / Assessment"
    ],
    "pageTitle": "School Operations Dashboard",
    "badge": "School / Training Workspace",
    "hero": "Track learners, staff, classes, assets, fees, tasks, documents, calendar activity, and support in one place.",
    "itemsTitle": "Classes / Assets / Materials",
    "itemSingular": "Class / Asset",
    "itemPlural": "Classes / Assets",
    "statusTitle": "Class / Asset Status",
    "progressTitle": "Training / Class Progress",
    "peopleTitle": "Staff / Learners",
    "peoplePrimary": "staff",
    "peopleSecondary": "learners",
    "peoplePrimaryTypes": [
      "staff",
      "teacher",
      "trainer",
      "manager"
    ],
    "peopleSecondaryTypes": [
      "student",
      "learner",
      "parent",
      "client",
      "lead"
    ],
    "pipelineTitle": "Learner Pipeline",
    "topPerformerTitle": "Top Staff Member",
    "calendarTitle": "Classes / Training",
    "previewTitle": "Classes / Assets Preview",
    "availableText": "active",
    "closedText": "completed"
  },
  {
    "key": "events",
    "name": "Events / Catering",
    "match": [
      "events",
      "catering",
      "caterer"
    ],
    "dashboardTitle": "Events Operations Dashboard",
    "chartsTitle": "Events Analytics",
    "itemsLabel": "Events / Orders / Equipment",
    "peopleLabel": "Staff / Clients",
    "tasksLabel": "Event Tasks",
    "recordsLabel": "Event / Client Records",
    "calendarLabel": "Event Schedule",
    "documentsLabel": "Event Documents",
    "incomeCategories": [
      "Event Payment",
      "Catering Payment",
      "Booking Deposit",
      "Service Fee",
      "Other Event Income"
    ],
    "expenseCategories": [
      "Food Supplies",
      "Staff Wages",
      "Transport",
      "Equipment Hire",
      "Venue Cost",
      "Marketing / Advertising",
      "Other Event Expense"
    ],
    "itemTypes": [
      "Event",
      "Order",
      "Equipment",
      "Package",
      "Service",
      "Booking"
    ],
    "peopleTypes": [
      "Planner",
      "Chef",
      "Staff",
      "Client",
      "Customer",
      "Supplier"
    ],
    "taskTypes": [
      "Event Preparation",
      "Client Follow-up",
      "Supplier Follow-up",
      "Payment Reminder",
      "Delivery Task",
      "Setup Task"
    ],
    "recordTypes": [
      "Event Update",
      "Client Note",
      "Supplier Note",
      "Payment Note",
      "Delivery Note",
      "Issue Log"
    ],
    "documentTypes": [
      "Quotation",
      "Invoice",
      "Receipt",
      "Client Agreement",
      "Supplier Document",
      "Event Document"
    ],
    "calendarTypes": [
      "Event Date",
      "Setup Date",
      "Client Meeting",
      "Supplier Follow-up",
      "Payment Reminder"
    ],
    "pageTitle": "Events Operations Dashboard",
    "badge": "Events / Catering Workspace",
    "hero": "Track events, bookings, clients, staff, suppliers, tasks, money records, and support in one place.",
    "itemsTitle": "Events / Orders / Equipment",
    "itemSingular": "Event / Order",
    "itemPlural": "Events / Orders",
    "statusTitle": "Event / Order Status",
    "progressTitle": "Event Progress",
    "peopleTitle": "Staff / Clients",
    "peoplePrimary": "staff",
    "peopleSecondary": "clients",
    "peoplePrimaryTypes": [
      "staff",
      "chef",
      "planner",
      "manager"
    ],
    "peopleSecondaryTypes": [
      "client",
      "customer",
      "supplier",
      "lead"
    ],
    "pipelineTitle": "Event / Client Pipeline",
    "topPerformerTitle": "Top Staff Member",
    "calendarTitle": "Event Schedule",
    "previewTitle": "Events / Orders Preview",
    "availableText": "active",
    "closedText": "completed"
  },
  {
    "key": "repair",
    "name": "Repair Shop",
    "match": [
      "repair",
      "repairs",
      "maintenance shop"
    ],
    "dashboardTitle": "Repair Shop Operations Dashboard",
    "chartsTitle": "Repair Shop Analytics",
    "itemsLabel": "Repair Jobs / Spare Parts",
    "peopleLabel": "Staff / Customers",
    "tasksLabel": "Repair Tasks",
    "recordsLabel": "Repair Records",
    "calendarLabel": "Repair Schedule",
    "documentsLabel": "Repair Documents",
    "incomeCategories": [
      "Repair Service",
      "Spare Part Sale",
      "Customer Payment",
      "Deposit",
      "Other Repair Income"
    ],
    "expenseCategories": [
      "Spare Parts",
      "Tools",
      "Staff Wages",
      "Rent",
      "Utilities",
      "Transport",
      "Other Repair Expense"
    ],
    "itemTypes": [
      "Repair Job",
      "Spare Part",
      "Tool",
      "Equipment",
      "Customer Item"
    ],
    "peopleTypes": [
      "Technician",
      "Staff",
      "Customer",
      "Client",
      "Supplier",
      "Manager"
    ],
    "taskTypes": [
      "Repair Follow-up",
      "Customer Update",
      "Spare Part Follow-up",
      "Payment Reminder",
      "Testing Task",
      "Delivery Task"
    ],
    "recordTypes": [
      "Repair Update",
      "Customer Note",
      "Spare Part Note",
      "Payment Note",
      "Issue Log",
      "Daily Update"
    ],
    "documentTypes": [
      "Receipt",
      "Invoice",
      "Job Card",
      "Supplier Document",
      "Customer Document"
    ],
    "calendarTypes": [
      "Repair Deadline",
      "Customer Pickup",
      "Supplier Follow-up",
      "Payment Reminder",
      "Testing Date"
    ],
    "pageTitle": "Repair Shop Operations Dashboard",
    "badge": "Repair Shop Workspace",
    "hero": "Track repair jobs, customers, staff, spare parts, tasks, money records, and support in one place.",
    "itemsTitle": "Repair Jobs / Spare Parts",
    "itemSingular": "Repair Job / Part",
    "itemPlural": "Repair Jobs / Parts",
    "statusTitle": "Repair / Part Status",
    "progressTitle": "Repair Progress",
    "peopleTitle": "Staff / Customers",
    "peoplePrimary": "staff",
    "peopleSecondary": "customers",
    "peoplePrimaryTypes": [
      "staff",
      "technician",
      "manager"
    ],
    "peopleSecondaryTypes": [
      "customer",
      "client",
      "supplier",
      "lead"
    ],
    "pipelineTitle": "Repair / Customer Pipeline",
    "topPerformerTitle": "Top Technician / Staff",
    "calendarTitle": "Repair Schedule",
    "previewTitle": "Repair Jobs / Parts Preview",
    "availableText": "available",
    "closedText": "completed"
  },
  {
    "key": "photography",
    "name": "Photography / Videography",
    "match": [
      "photography",
      "videography",
      "photo",
      "video"
    ],
    "dashboardTitle": "Photography Operations Dashboard",
    "chartsTitle": "Photography Analytics",
    "itemsLabel": "Shoots / Projects / Equipment",
    "peopleLabel": "Staff / Clients",
    "tasksLabel": "Shoot / Project Tasks",
    "recordsLabel": "Project Records",
    "calendarLabel": "Shoot Schedule",
    "documentsLabel": "Creative Documents",
    "incomeCategories": [
      "Shoot Payment",
      "Editing Fee",
      "Booking Deposit",
      "Delivery Fee",
      "Other Creative Income"
    ],
    "expenseCategories": [
      "Equipment",
      "Transport",
      "Assistant Payment",
      "Editing Cost",
      "Software",
      "Marketing / Advertising",
      "Other Creative Expense"
    ],
    "itemTypes": [
      "Shoot",
      "Project",
      "Equipment",
      "Package",
      "Delivery"
    ],
    "peopleTypes": [
      "Photographer",
      "Videographer",
      "Editor",
      "Staff",
      "Client",
      "Customer"
    ],
    "taskTypes": [
      "Shoot Task",
      "Editing Task",
      "Client Approval",
      "Delivery Follow-up",
      "Payment Reminder",
      "Equipment Check"
    ],
    "recordTypes": [
      "Shoot Note",
      "Editing Update",
      "Client Update",
      "Delivery Note",
      "Payment Note",
      "Issue Log"
    ],
    "documentTypes": [
      "Quotation",
      "Invoice",
      "Receipt",
      "Client Agreement",
      "Delivery File",
      "Project Document"
    ],
    "calendarTypes": [
      "Shoot Date",
      "Editing Deadline",
      "Delivery Date",
      "Client Meeting",
      "Payment Reminder"
    ],
    "pageTitle": "Photography Operations Dashboard",
    "badge": "Creative Services Workspace",
    "hero": "Track shoots, projects, clients, staff, equipment, tasks, money records, and delivery follow-ups in one place.",
    "itemsTitle": "Shoots / Projects / Equipment",
    "itemSingular": "Shoot / Project",
    "itemPlural": "Shoots / Projects",
    "statusTitle": "Shoot / Project Status",
    "progressTitle": "Project Progress",
    "peopleTitle": "Staff / Clients",
    "peoplePrimary": "staff",
    "peopleSecondary": "clients",
    "peoplePrimaryTypes": [
      "staff",
      "photographer",
      "videographer",
      "editor"
    ],
    "peopleSecondaryTypes": [
      "client",
      "customer",
      "lead"
    ],
    "pipelineTitle": "Client / Project Pipeline",
    "topPerformerTitle": "Top Staff Member",
    "calendarTitle": "Shoot Schedule",
    "previewTitle": "Shoots / Projects Preview",
    "availableText": "active",
    "closedText": "completed"
  },
  {
    "key": "car_hire",
    "name": "Car Hire / Car Rental",
    "match": [
      "car hire",
      "car rental",
      "rental car"
    ],
    "dashboardTitle": "Car Hire Operations Dashboard",
    "chartsTitle": "Car Hire Analytics",
    "itemsLabel": "Vehicles / Bookings",
    "peopleLabel": "Drivers / Customers",
    "tasksLabel": "Booking / Vehicle Tasks",
    "recordsLabel": "Rental Records",
    "calendarLabel": "Bookings / Vehicle Schedule",
    "documentsLabel": "Vehicle / Rental Documents",
    "incomeCategories": [
      "Rental Payment",
      "Booking Deposit",
      "Driver Fee",
      "Delivery Fee",
      "Other Car Hire Income"
    ],
    "expenseCategories": [
      "Fuel",
      "Vehicle Maintenance",
      "Insurance",
      "Driver Payment",
      "Cleaning",
      "Licensing",
      "Other Car Hire Expense"
    ],
    "itemTypes": [
      "Vehicle",
      "Booking",
      "Asset",
      "Service",
      "Maintenance Record"
    ],
    "peopleTypes": [
      "Driver",
      "Staff",
      "Customer",
      "Client",
      "Supplier",
      "Mechanic"
    ],
    "taskTypes": [
      "Booking Follow-up",
      "Vehicle Service",
      "Customer Follow-up",
      "Payment Reminder",
      "Document Collection",
      "Vehicle Return"
    ],
    "recordTypes": [
      "Booking Update",
      "Vehicle Update",
      "Customer Note",
      "Maintenance Record",
      "Payment Note",
      "Incident Log"
    ],
    "documentTypes": [
      "Rental Agreement",
      "Vehicle Document",
      "Insurance",
      "Receipt",
      "Invoice",
      "Client ID"
    ],
    "calendarTypes": [
      "Booking Date",
      "Vehicle Return",
      "Vehicle Service",
      "Payment Reminder",
      "Client Follow-up"
    ],
    "pageTitle": "Car Hire Operations Dashboard",
    "badge": "Car Hire Workspace",
    "hero": "Track vehicles, bookings, customers, drivers, tasks, money records, documents, and support in one place.",
    "itemsTitle": "Vehicles / Bookings",
    "itemSingular": "Vehicle / Booking",
    "itemPlural": "Vehicles / Bookings",
    "statusTitle": "Vehicle / Booking Status",
    "progressTitle": "Booking Progress",
    "peopleTitle": "Drivers / Customers",
    "peoplePrimary": "drivers",
    "peopleSecondary": "customers",
    "peoplePrimaryTypes": [
      "driver",
      "staff",
      "manager"
    ],
    "peopleSecondaryTypes": [
      "customer",
      "client",
      "lead"
    ],
    "pipelineTitle": "Booking Pipeline",
    "topPerformerTitle": "Top Driver / Staff",
    "calendarTitle": "Bookings / Vehicle Schedule",
    "previewTitle": "Vehicles / Bookings Preview",
    "availableText": "available",
    "closedText": "completed"
  },
  {
    "key": "furniture",
    "name": "Furniture / Carpentry",
    "match": [
      "furniture",
      "carpentry",
      "woodwork"
    ],
    "dashboardTitle": "Furniture Operations Dashboard",
    "chartsTitle": "Furniture Analytics",
    "itemsLabel": "Orders / Materials / Projects",
    "peopleLabel": "Staff / Clients",
    "tasksLabel": "Order / Workshop Tasks",
    "recordsLabel": "Order Records",
    "calendarLabel": "Order / Delivery Schedule",
    "documentsLabel": "Furniture Documents",
    "incomeCategories": [
      "Furniture Sale",
      "Custom Order Payment",
      "Deposit",
      "Delivery Fee",
      "Other Furniture Income"
    ],
    "expenseCategories": [
      "Materials",
      "Labour",
      "Transport",
      "Tools",
      "Workshop Rent",
      "Machine Maintenance",
      "Other Furniture Expense"
    ],
    "itemTypes": [
      "Order",
      "Furniture Item",
      "Material",
      "Project",
      "Tool",
      "Equipment"
    ],
    "peopleTypes": [
      "Carpenter",
      "Designer",
      "Staff",
      "Client",
      "Customer",
      "Supplier"
    ],
    "taskTypes": [
      "Order Task",
      "Material Follow-up",
      "Client Approval",
      "Delivery Follow-up",
      "Payment Reminder",
      "Workshop Task"
    ],
    "recordTypes": [
      "Order Update",
      "Material Note",
      "Client Approval",
      "Delivery Note",
      "Payment Note",
      "Issue Log"
    ],
    "documentTypes": [
      "Quotation",
      "Invoice",
      "Receipt",
      "Design Document",
      "Delivery Note",
      "Client Agreement"
    ],
    "calendarTypes": [
      "Order Deadline",
      "Delivery Date",
      "Client Approval",
      "Material Delivery",
      "Payment Reminder"
    ],
    "pageTitle": "Furniture Operations Dashboard",
    "badge": "Furniture / Carpentry Workspace",
    "hero": "Track orders, materials, projects, clients, staff, money records, tasks, and delivery follow-ups in one place.",
    "itemsTitle": "Orders / Materials / Projects",
    "itemSingular": "Order / Material",
    "itemPlural": "Orders / Materials",
    "statusTitle": "Order / Material Status",
    "progressTitle": "Order Progress",
    "peopleTitle": "Staff / Clients",
    "peoplePrimary": "staff",
    "peopleSecondary": "clients",
    "peoplePrimaryTypes": [
      "staff",
      "carpenter",
      "designer",
      "manager"
    ],
    "peopleSecondaryTypes": [
      "client",
      "customer",
      "supplier",
      "lead"
    ],
    "pipelineTitle": "Order Pipeline",
    "topPerformerTitle": "Top Staff Member",
    "calendarTitle": "Order / Delivery Schedule",
    "previewTitle": "Orders / Materials Preview",
    "availableText": "available",
    "closedText": "completed"
  },
  {
    "key": "agrovet",
    "name": "Agrovet / Farm Supplies",
    "match": [
      "agrovet",
      "farm",
      "farming",
      "agriculture"
    ],
    "dashboardTitle": "Agrovet Operations Dashboard",
    "chartsTitle": "Agrovet Analytics",
    "itemsLabel": "Farm Supplies / Stock",
    "peopleLabel": "Staff / Suppliers",
    "tasksLabel": "Stock / Supplier Tasks",
    "recordsLabel": "Stock / Sales Records",
    "calendarLabel": "Restock / Follow-ups",
    "documentsLabel": "Agrovet Documents",
    "incomeCategories": [
      "Product Sale",
      "Customer Payment",
      "Bulk Sale",
      "Other Agrovet Income"
    ],
    "expenseCategories": [
      "Stock Purchase",
      "Supplier Payment",
      "Transport",
      "Staff Wages",
      "Rent",
      "Utilities",
      "Other Agrovet Expense"
    ],
    "itemTypes": [
      "Farm Supply",
      "Stock Item",
      "Medicine",
      "Feed",
      "Equipment",
      "Supplier Item"
    ],
    "peopleTypes": [
      "Staff",
      "Customer",
      "Supplier",
      "Farmer",
      "Manager",
      "Sales Person"
    ],
    "taskTypes": [
      "Restock Reminder",
      "Supplier Follow-up",
      "Customer Follow-up",
      "Payment Reminder",
      "Stock Count",
      "Delivery Follow-up"
    ],
    "recordTypes": [
      "Sales Note",
      "Stock Update",
      "Supplier Update",
      "Customer Request",
      "Daily Update",
      "Expired / Damaged Stock"
    ],
    "documentTypes": [
      "Receipt",
      "Invoice",
      "Supplier Invoice",
      "Stock List",
      "Delivery Note",
      "Business Document"
    ],
    "calendarTypes": [
      "Restock Date",
      "Supplier Follow-up",
      "Delivery Date",
      "Payment Reminder",
      "Stock Count"
    ],
    "pageTitle": "Agrovet Operations Dashboard",
    "badge": "Agrovet Workspace",
    "hero": "Track stock, farm supplies, customers, suppliers, staff, money records, tasks, and support in one place.",
    "itemsTitle": "Farm Supplies / Stock",
    "itemSingular": "Supply / Stock",
    "itemPlural": "Supplies / Stock",
    "statusTitle": "Supply / Stock Status",
    "progressTitle": "Stock / Restock Progress",
    "peopleTitle": "Staff / Suppliers",
    "peoplePrimary": "staff",
    "peopleSecondary": "suppliers",
    "peoplePrimaryTypes": [
      "staff",
      "manager",
      "sales"
    ],
    "peopleSecondaryTypes": [
      "supplier",
      "customer",
      "client",
      "lead"
    ],
    "pipelineTitle": "Supplier / Customer Pipeline",
    "topPerformerTitle": "Top Staff Member",
    "calendarTitle": "Restock / Follow-ups",
    "previewTitle": "Supplies / Stock Preview",
    "availableText": "in stock",
    "closedText": "sold"
  },
  {
    "key": "tourism",
    "name": "Tourism & Travel",
    "match": [
      "tourism",
      "travel",
      "tour company",
      "tour operator",
      "safari",
      "excursion"
    ],
    "dashboardTitle": "Tourism Operations Dashboard",
    "chartsTitle": "Tourism Analytics",
    "itemsLabel": "Tours / Packages / Bookings",
    "peopleLabel": "Guides / Travelers",
    "tasksLabel": "Tour / Booking Tasks",
    "recordsLabel": "Tour / Client Records",
    "calendarLabel": "Tour Schedule / Bookings",
    "documentsLabel": "Tourism Documents",
    "incomeCategories": [
      "Tour Package Payment",
      "Booking Deposit",
      "Guide Fee",
      "Transport Fee",
      "Other Tourism Income"
    ],
    "expenseCategories": [
      "Transport / Fuel",
      "Guide Payment",
      "Accommodation Cost",
      "Permits / Park Fees",
      "Marketing / Advertising",
      "Other Tourism Expense"
    ],
    "itemTypes": [
      "Tour Package",
      "Booking",
      "Vehicle",
      "Equipment",
      "Asset"
    ],
    "peopleTypes": [
      "Guide",
      "Driver",
      "Staff",
      "Traveler",
      "Client",
      "Customer",
      "Supplier"
    ],
    "taskTypes": [
      "Booking Follow-up",
      "Itinerary Preparation",
      "Client Follow-up",
      "Payment Reminder",
      "Document Collection"
    ],
    "recordTypes": [
      "Tour Update",
      "Client Note",
      "Booking Update",
      "Incident Log",
      "Daily Update"
    ],
    "documentTypes": [
      "Itinerary",
      "Invoice",
      "Receipt",
      "Client Agreement",
      "Permit / Park Document",
      "Travel Document"
    ],
    "calendarTypes": [
      "Tour Date",
      "Client Meeting",
      "Payment Reminder",
      "Departure Date"
    ],
    "pageTitle": "Tourism Operations Dashboard",
    "badge": "Tourism Workspace",
    "hero": "Track tours, bookings, guides, travelers, itineraries, tasks, money records, documents, and support in one place.",
    "itemsTitle": "Tours / Packages / Bookings",
    "itemSingular": "Tour / Booking",
    "itemPlural": "Tours / Bookings",
    "statusTitle": "Tour / Booking Status",
    "progressTitle": "Booking Progress",
    "peopleTitle": "Guides / Travelers",
    "peoplePrimary": "guides",
    "peopleSecondary": "travelers",
    "peoplePrimaryTypes": [
      "guide",
      "driver",
      "staff"
    ],
    "peopleSecondaryTypes": [
      "traveler",
      "client",
      "customer",
      "lead"
    ],
    "pipelineTitle": "Client / Booking Pipeline",
    "topPerformerTitle": "Top Guide / Staff",
    "calendarTitle": "Tour Schedule / Bookings",
    "previewTitle": "Tours / Bookings Preview",
    "availableText": "available",
    "closedText": "completed"
  },
  {
    "key": "wholesale",
    "name": "Wholesale & Distribution",
    "match": [
      "wholesale",
      "distribution",
      "distributor",
      "bulk supply",
      "bulk supplier"
    ],
    "dashboardTitle": "Wholesale Operations Dashboard",
    "chartsTitle": "Wholesale Analytics",
    "itemsLabel": "Stock / Bulk Inventory",
    "peopleLabel": "Staff / Retailers",
    "tasksLabel": "Order / Delivery Tasks",
    "recordsLabel": "Order / Stock Records",
    "calendarLabel": "Delivery / Restock Schedule",
    "documentsLabel": "Wholesale Documents",
    "incomeCategories": [
      "Bulk Sale",
      "Retailer Payment",
      "Distribution Fee",
      "Delivery Fee",
      "Other Wholesale Income"
    ],
    "expenseCategories": [
      "Stock Purchase",
      "Supplier Payment",
      "Transport / Delivery",
      "Staff Wages",
      "Warehousing Cost",
      "Other Wholesale Expense"
    ],
    "itemTypes": [
      "Stock Item",
      "Bulk Product",
      "Pallet",
      "Container",
      "Asset"
    ],
    "peopleTypes": [
      "Staff",
      "Retailer",
      "Distributor",
      "Supplier",
      "Driver",
      "Manager"
    ],
    "taskTypes": [
      "Order Follow-up",
      "Delivery Follow-up",
      "Restock Reminder",
      "Payment Reminder",
      "Stock Count"
    ],
    "recordTypes": [
      "Order Update",
      "Stock Update",
      "Delivery Note",
      "Retailer Update",
      "Daily Update"
    ],
    "documentTypes": [
      "Purchase Order",
      "Invoice",
      "Receipt",
      "Delivery Note",
      "Stock List",
      "Business Document"
    ],
    "calendarTypes": [
      "Delivery Date",
      "Restock Date",
      "Retailer Follow-up",
      "Payment Reminder",
      "Stock Count"
    ],
    "pageTitle": "Wholesale Operations Dashboard",
    "badge": "Wholesale Workspace",
    "hero": "Track bulk stock, orders, retailers, deliveries, tasks, money records, documents, and support in one place.",
    "itemsTitle": "Stock / Bulk Inventory",
    "itemSingular": "Stock Item",
    "itemPlural": "Stock Items",
    "statusTitle": "Stock Status",
    "progressTitle": "Order / Delivery Progress",
    "peopleTitle": "Staff / Retailers",
    "peoplePrimary": "staff",
    "peopleSecondary": "retailers",
    "peoplePrimaryTypes": [
      "staff",
      "manager",
      "driver"
    ],
    "peopleSecondaryTypes": [
      "retailer",
      "distributor",
      "customer",
      "supplier",
      "lead"
    ],
    "pipelineTitle": "Retailer / Order Pipeline",
    "topPerformerTitle": "Top Staff Member",
    "calendarTitle": "Delivery / Restock Schedule",
    "previewTitle": "Stock Preview",
    "availableText": "in stock",
    "closedText": "delivered"
  }
];

  const GENERAL = {
  "key": "general",
  "name": "General Business Operations",
  "dashboardTitle": "Business Operations Dashboard",
  "chartsTitle": "Business Analytics",
  "itemsLabel": "Items / Assets / Stock",
  "peopleLabel": "People / Contacts",
  "tasksLabel": "Tasks / Follow-ups",
  "recordsLabel": "Business Records",
  "calendarLabel": "Calendar Activities",
  "documentsLabel": "Documents",
  "incomeCategories": [
    "Sales Income",
    "Service Income",
    "Customer Payment",
    "Deposit",
    "Other Income"
  ],
  "expenseCategories": [
    "Staff Wages",
    "Supplies",
    "Transport",
    "Marketing / Advertising",
    "Rent",
    "Utilities",
    "Maintenance / Repairs",
    "Other Expense"
  ],
  "itemTypes": [
    "Stock Item",
    "Asset",
    "Equipment",
    "Service",
    "Project",
    "Other"
  ],
  "peopleTypes": [
    "Owner",
    "Manager",
    "Staff",
    "Client",
    "Customer",
    "Supplier",
    "Lead",
    "Contact"
  ],
  "taskTypes": [
    "Follow-up",
    "Payment Reminder",
    "Document Collection",
    "Delivery",
    "Maintenance",
    "Meeting",
    "General Task"
  ],
  "recordTypes": [
    "Daily Update",
    "Client Update",
    "Payment Note",
    "Work Progress",
    "Issue Log",
    "General Record"
  ],
  "documentTypes": [
    "Agreement",
    "Receipt",
    "Invoice",
    "Business Document",
    "Staff Document",
    "Client Document",
    "Other Document"
  ],
  "calendarTypes": [
    "Meeting",
    "Follow-up",
    "Payment Reminder",
    "Delivery",
    "Appointment",
    "Task Deadline",
    "Other Event"
  ],
  "reportSections": [
    "Money Summary",
    "Tasks Summary",
    "Records Summary",
    "Items / Assets Summary",
    "People Summary",
    "Documents Summary",
    "Support Summary"
  ],
  "pageTitle": "Business Operations Dashboard",
  "badge": "Business Workspace",
  "hero": "Track operations, items, people, tasks, money records, documents, calendar activity, and support in one place.",
  "itemsTitle": "Items / Assets / Stock",
  "itemSingular": "Item / Asset",
  "itemPlural": "Items / Assets",
  "statusTitle": "Item / Asset Status",
  "progressTitle": "Work Progress",
  "peopleTitle": "People / Contacts",
  "peoplePrimary": "staff",
  "peopleSecondary": "contacts",
  "peoplePrimaryTypes": [
    "staff",
    "manager",
    "worker",
    "operator"
  ],
  "peopleSecondaryTypes": [
    "client",
    "customer",
    "supplier",
    "lead",
    "contact"
  ],
  "pipelineTitle": "People / Customer Pipeline",
  "topPerformerTitle": "Top Performer",
  "calendarTitle": "Calendar Activity",
  "previewTitle": "Items / Assets Preview",
  "availableText": "available",
  "closedText": "completed"
};

  function getRawBusinessText(tenant) {
    return [
      getValue(tenant, ["business_type_key"], ""),
      getValue(tenant, ["business_type"], ""),
      getValue(tenant, ["business_category"], ""),
      getValue(tenant, ["industry"], ""),
      getValue(tenant, ["name", "business_name", "company_name"], "")
    ].join(" ").toLowerCase();
  }

  function resolve(tenant) {
    const raw = getRawBusinessText(tenant);

    for (let i = 0; i < TYPES.length; i++) {
      const type = TYPES[i];

      for (let j = 0; j < type.match.length; j++) {
        if (raw.includes(type.match[j])) {
          return type;
        }
      }
    }

    return null;
  }

  function getValue(obj, fields, fallback) {
    if (!obj) return fallback === undefined ? "" : fallback;

    for (let i = 0; i < fields.length; i++) {
      const key = fields[i];

      if (
        Object.prototype.hasOwnProperty.call(obj, key) &&
        obj[key] !== null &&
        obj[key] !== undefined &&
        obj[key] !== ""
      ) {
        return obj[key];
      }
    }

    return fallback === undefined ? "" : fallback;
  }

  window.UnganiBusinessConfig = {
    TYPES,
    GENERAL,
    resolve,
    getRawBusinessText,
    getValue
  };
})();
