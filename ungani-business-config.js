(function () {
  // Single source of truth for per-business-type dashboard labels, chart
  // copy, default categories, AND business sub-sections (e.g. Hotel,
  // Restaurant, Bar within Hospitality). Both ungani-presets.js
  // (dashboard labels/categories) and ungani-analytics.js (chart
  // titles/copy) read from this file instead of maintaining their own
  // separate lists, so every business type gets identical treatment
  // everywhere it's used.
  //
  // Matching is fuzzy substring matching against the tenant's
  // business_type_key + business_type + business_name text, first match
  // in TYPES order wins.
  //
  // Sections: a type may define a "sections" array (e.g. Hospitality has
  // Hotel, Restaurant, Bar / Lounge, ...). Each section contributes
  // additional item/people/task/record/document/calendar types and
  // income/expense categories on top of the base type. When a tenant has
  // multiple sections selected (tenant.selected_sections, an array of
  // section labels), resolveWithSections() merges every matching
  // section's additions into the base type - so Hotel + Restaurant
  // genuinely combines both sets of categories, not just one.

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
    "closedText": "completed",
    "sections": [
      {
        "key": "transport",
        "label": "Transport",
        "itemTypes": [
          "Truck",
          "Vehicle",
          "Trip"
        ],
        "peopleTypes": [
          "Driver"
        ],
        "incomeCategories": [
          "Trip Payment",
          "Transport Income"
        ],
        "expenseCategories": [
          "Fuel",
          "Driver Allowance",
          "Toll / Parking"
        ],
        "taskTypes": [
          "Trip Follow-up",
          "Delivery Confirmation"
        ],
        "documentTypes": [
          "Delivery Note",
          "Trip Document"
        ],
        "calendarTypes": [
          "Trip Date",
          "Delivery Date"
        ]
      },
      {
        "key": "cold_chain",
        "label": "Cold Chain",
        "itemTypes": [
          "Genset",
          "Reefer"
        ],
        "peopleTypes": [
          "Mechanic"
        ],
        "incomeCategories": [
          "Cold Chain Service Fee"
        ],
        "expenseCategories": [
          "Genset / Reefer Maintenance"
        ],
        "taskTypes": [
          "Maintenance Reminder"
        ],
        "documentTypes": [
          "Insurance Document"
        ],
        "calendarTypes": [
          "Vehicle Service"
        ]
      },
      {
        "key": "clearing_forwarding",
        "label": "Clearing & Forwarding",
        "itemTypes": [
          "Container"
        ],
        "peopleTypes": [
          "Supervisor"
        ],
        "incomeCategories": [
          "Clearing / Forwarding Fee"
        ],
        "expenseCategories": [
          "Documentation"
        ],
        "taskTypes": [
          "Document Collection"
        ],
        "documentTypes": [
          "Client Agreement"
        ],
        "calendarTypes": [
          "Document Deadline"
        ]
      }
    ]
  },
  {
    "key": "real_estate",
    "name": "Real Estate / Property Management",
    "match": [
      "real estate",
      "property",
      "properties",
      "housing",
      "land agency",
      "land developer",
      "land developers"
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
    "closedText": "sold/rented",
    "sections": [
      {
        "key": "rentals",
        "label": "Rentals",
        "itemTypes": [
          "Rental Unit",
          "Apartment",
          "House"
        ],
        "incomeCategories": [
          "Rental Income",
          "Booking Deposit"
        ],
        "expenseCategories": [
          "Property Maintenance"
        ],
        "taskTypes": [
          "Payment Reminder",
          "Maintenance Follow-up"
        ],
        "documentTypes": [
          "Lease Agreement"
        ],
        "calendarTypes": [
          "Payment Reminder"
        ]
      },
      {
        "key": "sales",
        "label": "Sales",
        "itemTypes": [
          "Apartment",
          "House",
          "Villa",
          "Land",
          "Commercial Unit"
        ],
        "incomeCategories": [
          "Property Sale",
          "Agency / Service Fee"
        ],
        "expenseCategories": [
          "Agent Commission",
          "Marketing / Advertising",
          "Legal / Documentation Fees"
        ],
        "taskTypes": [
          "Lead Follow-up",
          "Viewing Schedule",
          "Document Collection"
        ],
        "documentTypes": [
          "Sale Agreement",
          "Title Document"
        ],
        "calendarTypes": [
          "Viewing",
          "Client Meeting"
        ]
      }
    ]
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
      "night club",
      "nightclub",
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
    ],
    "sections": [
      {
        "key": "hotel",
        "label": "Hotel",
        "itemTypes": [
          "Room",
          "Suite"
        ],
        "incomeCategories": [
          "Room Booking Income"
        ],
        "expenseCategories": [
          "Housekeeping Supplies"
        ],
        "taskTypes": [
          "Housekeeping Task"
        ],
        "documentTypes": [
          "Booking Confirmation"
        ],
        "calendarTypes": [
          "Room Booking"
        ]
      },
      {
        "key": "guest_house",
        "label": "Guest House",
        "itemTypes": [
          "Guest Room"
        ],
        "incomeCategories": [
          "Guest House Booking Income"
        ],
        "expenseCategories": [
          "Housekeeping Supplies"
        ],
        "taskTypes": [
          "Guest Check-in / Check-out"
        ],
        "documentTypes": [
          "Booking Confirmation"
        ],
        "calendarTypes": [
          "Guest Booking"
        ]
      },
      {
        "key": "lodge",
        "label": "Lodge",
        "itemTypes": [
          "Cabin",
          "Room"
        ],
        "incomeCategories": [
          "Lodge Booking Income"
        ],
        "expenseCategories": [
          "Grounds Maintenance"
        ],
        "taskTypes": [
          "Guest Request"
        ],
        "documentTypes": [
          "Booking Confirmation"
        ],
        "calendarTypes": [
          "Lodge Booking"
        ]
      },
      {
        "key": "resort",
        "label": "Resort",
        "itemTypes": [
          "Villa",
          "Suite",
          "Recreational Facility"
        ],
        "incomeCategories": [
          "Resort Package Income"
        ],
        "expenseCategories": [
          "Facility Maintenance"
        ],
        "taskTypes": [
          "Activity Booking"
        ],
        "documentTypes": [
          "Package Agreement"
        ],
        "calendarTypes": [
          "Resort Booking"
        ]
      },
      {
        "key": "hostel",
        "label": "Hostel",
        "itemTypes": [
          "Dorm Bed",
          "Shared Room"
        ],
        "incomeCategories": [
          "Hostel Booking Income"
        ],
        "expenseCategories": [
          "Shared Facility Supplies"
        ],
        "taskTypes": [
          "Bed Assignment"
        ],
        "documentTypes": [
          "Booking Confirmation"
        ],
        "calendarTypes": [
          "Hostel Booking"
        ]
      },
      {
        "key": "airbnb",
        "label": "Airbnb / Vacation Rental",
        "itemTypes": [
          "Rental Unit"
        ],
        "incomeCategories": [
          "Vacation Rental Income"
        ],
        "expenseCategories": [
          "Cleaning / Turnover Cost"
        ],
        "taskTypes": [
          "Guest Check-in / Check-out",
          "Turnover Cleaning"
        ],
        "documentTypes": [
          "Rental Agreement"
        ],
        "calendarTypes": [
          "Rental Booking"
        ]
      },
      {
        "key": "restaurant",
        "label": "Restaurant",
        "itemTypes": [
          "Table",
          "Menu Item"
        ],
        "peopleTypes": [
          "Chef",
          "Waiter"
        ],
        "incomeCategories": [
          "Restaurant / Food Sales"
        ],
        "expenseCategories": [
          "Food Supplies"
        ],
        "taskTypes": [
          "Table Reservation"
        ],
        "documentTypes": [
          "Menu"
        ],
        "calendarTypes": [
          "Table Reservation"
        ]
      },
      {
        "key": "bar_lounge",
        "label": "Bar / Lounge",
        "itemTypes": [
          "Beverage",
          "Bar Stock"
        ],
        "peopleTypes": [
          "Bartender"
        ],
        "incomeCategories": [
          "Bar / Beverage Sales"
        ],
        "expenseCategories": [
          "Beverage Supplies"
        ],
        "taskTypes": [
          "Stock Restock"
        ],
        "documentTypes": [
          "Supplier Invoice"
        ],
        "calendarTypes": [
          "Event Night"
        ]
      },
      {
        "key": "catering",
        "label": "Catering",
        "itemTypes": [
          "Catering Order",
          "Equipment"
        ],
        "peopleTypes": [
          "Caterer"
        ],
        "incomeCategories": [
          "Catering Payment"
        ],
        "expenseCategories": [
          "Food Supplies",
          "Equipment Hire"
        ],
        "taskTypes": [
          "Event Preparation"
        ],
        "documentTypes": [
          "Catering Quotation"
        ],
        "calendarTypes": [
          "Catering Event Date"
        ]
      }
    ]
  },
  {
    "key": "automotive",
    "name": "Automotive Services",
    "match": [
      "car wash",
      "auto detailing",
      "detailing",
      "car hire",
      "car rental",
      "rental car",
      "repair",
      "repairs",
      "maintenance shop",
      "automotive"
    ],
    "dashboardTitle": "Automotive Operations Dashboard",
    "chartsTitle": "Automotive Analytics",
    "itemsLabel": "Vehicles / Services / Parts",
    "peopleLabel": "Staff / Customers",
    "tasksLabel": "Service / Booking Tasks",
    "recordsLabel": "Service Records",
    "calendarLabel": "Bookings / Service Schedule",
    "documentsLabel": "Automotive Documents",
    "incomeCategories": [
      "Customer Payment",
      "Other Automotive Income"
    ],
    "expenseCategories": [
      "Staff Wages",
      "Marketing / Advertising",
      "Other Automotive Expense"
    ],
    "itemTypes": [
      "Vehicle",
      "Equipment"
    ],
    "peopleTypes": [
      "Staff",
      "Customer",
      "Manager",
      "Supplier"
    ],
    "taskTypes": [
      "Customer Follow-up",
      "Payment Reminder"
    ],
    "recordTypes": [
      "Service Record",
      "Customer Feedback"
    ],
    "documentTypes": [
      "Receipt",
      "Invoice"
    ],
    "calendarTypes": [
      "Booking",
      "Payment Reminder"
    ],
    "pageTitle": "Automotive Operations Dashboard",
    "badge": "Automotive Workspace",
    "hero": "Track vehicles, services, bookings, customers, staff, money records, tasks, and support in one place.",
    "itemsTitle": "Vehicles / Services / Parts",
    "itemSingular": "Vehicle / Service",
    "itemPlural": "Vehicles / Services",
    "statusTitle": "Vehicle / Service Status",
    "progressTitle": "Booking / Service Progress",
    "peopleTitle": "Staff / Customers",
    "peoplePrimary": "staff",
    "peopleSecondary": "customers",
    "peoplePrimaryTypes": [
      "staff",
      "manager",
      "technician"
    ],
    "peopleSecondaryTypes": [
      "customer",
      "client",
      "lead"
    ],
    "pipelineTitle": "Customer / Booking Pipeline",
    "topPerformerTitle": "Top Staff Member",
    "calendarTitle": "Bookings / Service Schedule",
    "previewTitle": "Vehicles / Services Preview",
    "availableText": "available",
    "closedText": "completed",
    "sections": [
      {
        "key": "car_wash",
        "label": "Car Wash / Detailing",
        "itemTypes": [
          "Service",
          "Cleaning Product",
          "Equipment",
          "Package",
          "Booking"
        ],
        "peopleTypes": [
          "Washer",
          "Detailer"
        ],
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
        "documentTypes": [
          "Receipt"
        ],
        "calendarTypes": [
          "Booking"
        ]
      },
      {
        "key": "car_hire",
        "label": "Car Hire / Rental",
        "itemTypes": [
          "Vehicle",
          "Booking",
          "Asset",
          "Service",
          "Maintenance Record"
        ],
        "peopleTypes": [
          "Driver"
        ],
        "incomeCategories": [
          "Rental Payment",
          "Booking Deposit",
          "Driver Fee",
          "Delivery Fee",
          "Other Car Hire Income"
        ],
        "expenseCategories": [
          "Vehicle Maintenance",
          "Insurance",
          "Fuel",
          "Driver Payment",
          "Cleaning",
          "Licensing",
          "Other Car Hire Expense"
        ],
        "documentTypes": [
          "Rental Agreement"
        ],
        "calendarTypes": [
          "Vehicle Return"
        ]
      },
      {
        "key": "repair_shop",
        "label": "Repair Shop",
        "itemTypes": [
          "Repair Job",
          "Spare Part",
          "Tool",
          "Equipment",
          "Customer Item"
        ],
        "peopleTypes": [
          "Technician"
        ],
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
        "documentTypes": [
          "Job Card"
        ],
        "calendarTypes": [
          "Repair Deadline"
        ]
      }
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
    "closedText": "completed",
    "sections": [
      {
        "key": "salon_sec",
        "label": "Salon",
        "itemTypes": [
          "Hair Service"
        ],
        "peopleTypes": [
          "Stylist"
        ],
        "incomeCategories": [
          "Hair Service Income"
        ],
        "documentTypes": [
          "Receipt"
        ],
        "calendarTypes": [
          "Appointment"
        ]
      },
      {
        "key": "barber_sec",
        "label": "Barber",
        "itemTypes": [
          "Barber Service"
        ],
        "peopleTypes": [
          "Barber"
        ],
        "incomeCategories": [
          "Barber Service Income"
        ],
        "documentTypes": [
          "Receipt"
        ],
        "calendarTypes": [
          "Appointment"
        ]
      },
      {
        "key": "spa_sec",
        "label": "Spa",
        "itemTypes": [
          "Spa Treatment"
        ],
        "peopleTypes": [
          "Therapist"
        ],
        "incomeCategories": [
          "Spa Treatment Income"
        ],
        "documentTypes": [
          "Receipt"
        ],
        "calendarTypes": [
          "Appointment"
        ]
      },
      {
        "key": "beauty_sec",
        "label": "Beauty Services",
        "itemTypes": [
          "Beauty Treatment",
          "Cosmetic Product"
        ],
        "incomeCategories": [
          "Beauty Service Income"
        ],
        "documentTypes": [
          "Receipt"
        ],
        "calendarTypes": [
          "Appointment"
        ]
      }
    ]
  },
  {
    "key": "printing",
    "name": "Printing / Branding Company",
    "match": [
      "printing",
      "branding",
      "print",
      "graphic design",
      "design studio",
      "design agency"
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
    "key": "retail",
    "name": "Retail",
    "match": [
      "retail",
      "mini market",
      "shop",
      "store",
      "pharmacy",
      "chemist",
      "medicine",
      "agrovet",
      "farm",
      "farming",
      "agriculture"
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
    "closedText": "sold",
    "sections": [
      {
        "key": "electronics",
        "label": "Electronics & Computers",
        "itemTypes": [
          "Electronics",
          "Computer",
          "Accessory"
        ],
        "incomeCategories": [
          "Electronics Sale"
        ],
        "expenseCategories": [
          "Electronics Stock Purchase"
        ],
        "documentTypes": [
          "Warranty Card"
        ],
        "calendarTypes": [
          "Restock Date"
        ]
      },
      {
        "key": "mobile_phones",
        "label": "Mobile Phones & Accessories",
        "itemTypes": [
          "Mobile Phone",
          "Phone Accessory"
        ],
        "incomeCategories": [
          "Mobile Phone Sale",
          "Repair Service"
        ],
        "expenseCategories": [
          "Phone Stock Purchase"
        ],
        "documentTypes": [
          "Warranty Card"
        ],
        "calendarTypes": [
          "Restock Date"
        ]
      },
      {
        "key": "supermarket",
        "label": "Supermarket & Grocery",
        "itemTypes": [
          "Grocery Item",
          "FMCG Product"
        ],
        "incomeCategories": [
          "Grocery Sale"
        ],
        "expenseCategories": [
          "Grocery Stock Purchase"
        ],
        "documentTypes": [
          "Stock List"
        ],
        "calendarTypes": [
          "Restock Date"
        ]
      },
      {
        "key": "hardware",
        "label": "Hardware",
        "itemTypes": [
          "Hardware Item",
          "Tool",
          "Building Material"
        ],
        "incomeCategories": [
          "Hardware Sale"
        ],
        "expenseCategories": [
          "Hardware Stock Purchase"
        ],
        "documentTypes": [
          "Stock List"
        ],
        "calendarTypes": [
          "Restock Date"
        ]
      },
      {
        "key": "agrovet",
        "label": "Agrovet",
        "itemTypes": [
          "Farm Supply",
          "Feed",
          "Medicine",
          "Stock Item",
          "Equipment",
          "Supplier Item"
        ],
        "peopleTypes": [
          "Farmer"
        ],
        "incomeCategories": [
          "Agrovet Product Sale",
          "Product Sale",
          "Customer Payment",
          "Bulk Sale",
          "Other Agrovet Income"
        ],
        "expenseCategories": [
          "Agrovet Stock Purchase",
          "Stock Purchase",
          "Supplier Payment",
          "Transport",
          "Staff Wages",
          "Rent",
          "Utilities",
          "Other Agrovet Expense"
        ],
        "documentTypes": [
          "Stock List"
        ],
        "calendarTypes": [
          "Restock Date"
        ]
      },
      {
        "key": "pharmacy",
        "label": "Pharmacy",
        "itemTypes": [
          "Medicine",
          "Medical Supply",
          "Stock Item",
          "Equipment",
          "Supplier Item"
        ],
        "peopleTypes": [
          "Pharmacist"
        ],
        "incomeCategories": [
          "Medicine Sale",
          "Prescription Sale",
          "Customer Payment",
          "Other Pharmacy Income"
        ],
        "expenseCategories": [
          "Medicine Purchase",
          "Licensing",
          "Expired Stock Loss",
          "Supplier Payment",
          "Staff Wages",
          "Rent",
          "Utilities",
          "Other Pharmacy Expense"
        ],
        "documentTypes": [
          "License"
        ],
        "calendarTypes": [
          "Expiry Check"
        ]
      },
      {
        "key": "fashion",
        "label": "Fashion & Boutique",
        "itemTypes": [
          "Clothing Item",
          "Accessory",
          "Footwear",
          "Stock Item",
          "Bundle"
        ],
        "incomeCategories": [
          "Fashion Sale",
          "Product Sale",
          "Customer Payment",
          "Bulk Sale",
          "Online Sale",
          "Other Boutique Income"
        ],
        "expenseCategories": [
          "Fashion Stock Purchase",
          "Stock Purchase",
          "Supplier Payment",
          "Staff Wages",
          "Rent",
          "Packaging",
          "Marketing / Advertising",
          "Other Boutique Expense"
        ],
        "documentTypes": [
          "Stock List"
        ],
        "calendarTypes": [
          "Restock Date"
        ]
      },
      {
        "key": "furniture_retail",
        "label": "Furniture",
        "itemTypes": [
          "Furniture Item"
        ],
        "incomeCategories": [
          "Furniture Sale"
        ],
        "expenseCategories": [
          "Furniture Stock Purchase"
        ],
        "documentTypes": [
          "Delivery Note"
        ],
        "calendarTypes": [
          "Delivery Date"
        ]
      },
      {
        "key": "cosmetics",
        "label": "Cosmetics",
        "itemTypes": [
          "Cosmetic Product"
        ],
        "incomeCategories": [
          "Cosmetics Sale"
        ],
        "expenseCategories": [
          "Cosmetics Stock Purchase"
        ],
        "documentTypes": [
          "Stock List"
        ],
        "calendarTypes": [
          "Restock Date"
        ]
      },
      {
        "key": "bookshop",
        "label": "Bookshop",
        "itemTypes": [
          "Book",
          "Stationery"
        ],
        "incomeCategories": [
          "Book Sale",
          "Stationery Sale"
        ],
        "expenseCategories": [
          "Book Stock Purchase"
        ],
        "documentTypes": [
          "Stock List"
        ],
        "calendarTypes": [
          "Restock Date"
        ]
      },
      {
        "key": "general_retail",
        "label": "General Retail",
        "itemTypes": [
          "Product"
        ],
        "incomeCategories": [
          "Product Sale"
        ],
        "expenseCategories": [
          "Stock Purchase"
        ],
        "documentTypes": [
          "Stock List"
        ],
        "calendarTypes": [
          "Restock Date"
        ]
      }
    ]
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
      "facilities management",
      "facility management",
      "janitorial"
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
      "building contractor",
      "building contractors",
      "builders"
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
    "key": "healthcare",
    "name": "Healthcare",
    "match": [
      "clinic",
      "health",
      "medical",
      "hospital"
    ],
    "dashboardTitle": "Healthcare Operations Dashboard",
    "chartsTitle": "Healthcare Analytics",
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
    "pageTitle": "Healthcare Operations Dashboard",
    "badge": "Healthcare Workspace",
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
    "closedText": "completed",
    "sections": [
      {
        "key": "clinic",
        "label": "Clinic",
        "itemTypes": [
          "Consultation Room"
        ],
        "incomeCategories": [
          "Consultation Fee"
        ],
        "documentTypes": [
          "Patient Document"
        ],
        "calendarTypes": [
          "Appointment"
        ]
      },
      {
        "key": "medical_centre",
        "label": "Medical Centre",
        "itemTypes": [
          "Treatment Room",
          "Diagnostic Equipment"
        ],
        "incomeCategories": [
          "Treatment Fee"
        ],
        "documentTypes": [
          "Referral Letter"
        ],
        "calendarTypes": [
          "Appointment"
        ]
      },
      {
        "key": "hospital",
        "label": "Hospital",
        "itemTypes": [
          "Ward Bed",
          "Medical Equipment"
        ],
        "peopleTypes": [
          "Surgeon"
        ],
        "incomeCategories": [
          "Admission Fee",
          "Surgery Fee"
        ],
        "expenseCategories": [
          "Ward Supplies"
        ],
        "documentTypes": [
          "Admission Form"
        ],
        "calendarTypes": [
          "Surgery Schedule"
        ]
      },
      {
        "key": "dental",
        "label": "Dental Clinic",
        "itemTypes": [
          "Dental Equipment",
          "Dental Supply"
        ],
        "peopleTypes": [
          "Dentist"
        ],
        "incomeCategories": [
          "Dental Procedure Fee"
        ],
        "expenseCategories": [
          "Dental Supplies"
        ],
        "documentTypes": [
          "Patient Document"
        ],
        "calendarTypes": [
          "Appointment"
        ]
      },
      {
        "key": "lab",
        "label": "Diagnostic Laboratory",
        "itemTypes": [
          "Lab Equipment",
          "Test Kit"
        ],
        "peopleTypes": [
          "Lab Technician"
        ],
        "incomeCategories": [
          "Lab Test Fee"
        ],
        "expenseCategories": [
          "Lab Supplies",
          "Reagents"
        ],
        "documentTypes": [
          "Test Report"
        ],
        "calendarTypes": [
          "Sample Collection"
        ]
      }
    ]
  },
  {
    "key": "school",
    "name": "School / Training Center",
    "match": [
      "school",
      "preschool",
      "pre-school",
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
    "closedText": "completed",
    "sections": [
      {
        "key": "events_sec",
        "label": "Events / Functions",
        "itemTypes": [
          "Event"
        ],
        "peopleTypes": [
          "Planner"
        ],
        "incomeCategories": [
          "Event Payment"
        ],
        "expenseCategories": [
          "Venue Cost"
        ],
        "documentTypes": [
          "Event Document"
        ],
        "calendarTypes": [
          "Event Date"
        ]
      },
      {
        "key": "catering_sec",
        "label": "Catering",
        "itemTypes": [
          "Catering Order"
        ],
        "peopleTypes": [
          "Chef"
        ],
        "incomeCategories": [
          "Catering Payment"
        ],
        "expenseCategories": [
          "Food Supplies"
        ],
        "documentTypes": [
          "Catering Quotation"
        ],
        "calendarTypes": [
          "Catering Event Date"
        ]
      }
    ]
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

  const MERGEABLE_FIELDS = [
    "itemTypes", "peopleTypes", "incomeCategories", "expenseCategories",
    "taskTypes", "recordTypes", "documentTypes", "calendarTypes"
  ];

  function getRawBusinessText(tenant) {
    return [
      getValue(tenant, ["business_type_key"], ""),
      getValue(tenant, ["business_type"], ""),
      getValue(tenant, ["business_category"], ""),
      getValue(tenant, ["industry"], ""),
      getValue(tenant, ["name", "business_name", "company_name"], "")
    ].join(" ").toLowerCase();
  }

  // Plain raw.includes(keyword) matched a keyword as a substring ANYWHERE,
  // including inside an unrelated word - e.g. salon's "spa" keyword matched
  // inside "Sparkle" (as in "Sparkle Cleaning Services"), misclassifying a
  // cleaning business as a salon. Found while testing the 2026-07-21 batch
  // (Printing/Gym/Cleaning/Construction/Photography/Furniture), the same
  // day three OTHER keywords ("club"/"land"/"building") were found matching
  // as substrings of unrelated multi-word business names. Both are the same
  // underlying flaw - matching without word boundaries - so this checks the
  // keyword is bounded by non-alphanumeric characters (or string start/end)
  // on both sides, same idea as \b in regex but tolerant of the keyword
  // itself containing spaces (e.g. "real estate", "cold chain").
  function matchesKeyword(raw, keyword) {
    const escaped = keyword.replace(/[-/\\^$*+?.()|[\]{}]/g, "\\$&");
    const pattern = new RegExp("(^|[^a-z0-9])" + escaped + "([^a-z0-9]|$)");
    return pattern.test(raw);
  }

  function resolve(tenant) {
    const raw = getRawBusinessText(tenant);

    for (let i = 0; i < TYPES.length; i++) {
      const type = TYPES[i];

      for (let j = 0; j < type.match.length; j++) {
        if (matchesKeyword(raw, type.match[j])) {
          return type;
        }
      }
    }

    return null;
  }

  // Merges a resolved type (or null, for the no-match case) with GENERAL.
  // List fields (categories/types) are unioned rather than overwritten, so
  // every business type always has at least the universal General options
  // available alongside its own specific ones. Both ungani-presets.js and
  // ungani-analytics.js call this so their output can never drift apart
  // on this again.
  function mergeWithGeneral(type) {
    const source = type || {};
    const merged = Object.assign({}, GENERAL, source);

    MERGEABLE_FIELDS.forEach(function (field) {
      merged[field] = unique([].concat(source[field] || [], GENERAL[field] || []));
    });

    if (GENERAL.reportSections) {
      merged.reportSections = unique([].concat(source.reportSections || [], GENERAL.reportSections || []));
    }

    return merged;
  }

  function resolveWithSections(tenant) {
    const type = resolve(tenant);

    if (!type) return null;
    if (!type.sections || !type.sections.length) return type;

    const selected = getSelectedSections(tenant);

    if (!selected.length) return type;

    const matchedSections = type.sections.filter(function (section) {
      return selected.indexOf(section.label.toLowerCase()) !== -1;
    });

    if (!matchedSections.length) return type;

    const merged = Object.assign({}, type);

    MERGEABLE_FIELDS.forEach(function (field) {
      const combined = (type[field] || []).slice();

      matchedSections.forEach(function (section) {
        combined.push.apply(combined, section[field] || []);
      });

      merged[field] = unique(combined);
    });

    merged.selectedSectionLabels = matchedSections.map(function (section) {
      return section.label;
    });

    return merged;
  }

  function getSelectedSections(tenant) {
    const raw = getValue(tenant, ["selected_sections"], null);

    if (!raw || !raw.length) return [];

    return raw
      .map(function (value) { return String(value || "").trim().toLowerCase(); })
      .filter(Boolean);
  }

  function unique(values) {
    const seen = {};
    const output = [];

    (values || []).forEach(function (value) {
      const clean = String(value || "").trim();

      if (!clean) return;

      const key = clean.toLowerCase();

      if (!seen[key]) {
        seen[key] = true;
        output.push(clean);
      }
    });

    return output;
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

  // Phase 2: per-section "what does an item actually look like here"
  // field definitions for my-items.html's add/edit form and card display.
  // Keyed by section key first, falling back to the top-level type key,
  // falling back to GENERIC_ITEM_FIELD_SET for anything not covered yet
  // (Phase 3 will fill in the remaining ~20 sections one at a time).
  //
  // Each field: { id, label, type, placeholder?, column? }
  //   - type is "text" | "number" | "date" | "url"
  //   - column: if set, the value reads/writes that existing top-level
  //     business_items column (used only for Real Estate's legacy
  //     fields, so old data and any code still reading those columns
  //     directly - e.g. client.html's Property dashboard - keeps
  //     working unchanged). If absent, the value reads/writes
  //     custom_fields[id] instead.

  const GENERIC_ITEM_FIELD_SET = {
    valueLabel: "Price / Value",
    statusOptions: ["available", "in use", "maintenance", "inactive"],
    fields: [
      // id must be "stock_quantity", not "quantity" - client.html's
      // getStockQuantity()/isLowStockItem() (built for Retail's low-stock
      // KPI, now also used by Wholesale) read custom_fields.stock_quantity
      // specifically. This field previously used id "quantity", so every
      // business type on this generic fallback (Wholesale, Security,
      // School, and any Retail section without its own field set) silently
      // saved stock counts to a key nothing ever reads back - same class of
      // bug as the units_available mismatch fixed for Retail earlier.
      { id: "stock_quantity", label: "Quantity / Stock", type: "number", placeholder: "Example: 10" },
      { id: "supplier", label: "Supplier / Source", type: "text", placeholder: "Example: ABC Distributors" }
    ]
  };

  const REAL_ESTATE_ITEM_FIELD_SET = {
    valueLabel: "Price / Value",
    statusOptions: ["available", "reserved", "under negotiation", "sold", "rented", "maintenance", "inactive"],
    fields: [
      { id: "property_location", label: "Location", type: "text", column: "property_location", placeholder: "Example: Nyali, Mombasa" },
      { id: "bedrooms", label: "Bedrooms", type: "number", column: "bedrooms", placeholder: "Example: 3" },
      { id: "bathrooms", label: "Bathrooms", type: "number", column: "bathrooms", placeholder: "Example: 2" },
      { id: "property_size", label: "Property Size", type: "text", column: "property_size", placeholder: "Example: 1,250 sq ft" },
      { id: "assigned_agent", label: "Assigned Agent", type: "text", column: "assigned_agent", placeholder: "Example: Brian Otieno" },
      { id: "photo_url", label: "Photo URL", type: "url", column: "photo_url", placeholder: "Optional image link. If empty, placeholder is used." },
      { id: "project_name", label: "Project / Development", type: "text", column: "project_name", placeholder: "Example: Clove Garden" },
      { id: "date_listed", label: "Date Listed", type: "date", column: "date_listed" },
      { id: "total_units", label: "Total Units", type: "number", column: "total_units", placeholder: "Example: 20" },
      { id: "units_sold", label: "Units Sold", type: "number", column: "units_sold", placeholder: "Example: 8" },
      { id: "units_available", label: "Units Available", type: "number", column: "units_available", placeholder: "Example: 12" },
      { id: "project_progress_percent", label: "Project Progress %", type: "number", column: "project_progress_percent", placeholder: "Example: 65" },
      { id: "completion_status", label: "Completion Status", type: "text", column: "completion_status", placeholder: "Example: Ongoing / Ready / Completed" }
    ]
  };

  const LOGISTICS_TRANSPORT_FIELD_SET = {
    valueLabel: "Estimated Value",
    statusOptions: ["available", "in use", "in maintenance", "retired", "inactive"],
    fields: [
      { id: "registration_number", label: "Registration Number", type: "text", placeholder: "Example: KDA 123B" },
      { id: "capacity", label: "Capacity", type: "text", placeholder: "Example: 7 tonnes / 14 seats" },
      { id: "fuel_type", label: "Fuel Type", type: "text", placeholder: "Example: Diesel" },
      { id: "last_service_date", label: "Last Service Date", type: "date" }
    ]
  };

  const LOGISTICS_COLD_CHAIN_FIELD_SET = {
    valueLabel: "Estimated Value",
    statusOptions: ["available", "in use", "in maintenance", "retired", "inactive"],
    fields: [
      { id: "fuel_capacity_liters", label: "Fuel Capacity (Liters)", type: "number", placeholder: "Example: 200" },
      { id: "temperature_range", label: "Temperature Range", type: "text", placeholder: "Example: -18°C to -22°C" },
      { id: "last_service_date", label: "Last Service Date", type: "date" }
    ]
  };

  const LOGISTICS_CLEARING_FIELD_SET = {
    valueLabel: "Estimated Value",
    statusOptions: ["available", "in progress", "cleared", "on hold", "inactive"],
    fields: [
      { id: "reference_number", label: "Container / Reference Number", type: "text", placeholder: "Example: MSKU1234567" },
      { id: "origin", label: "Origin", type: "text", placeholder: "Example: Mombasa Port" },
      { id: "destination", label: "Destination", type: "text", placeholder: "Example: Nairobi ICD" },
      { id: "clearance_status", label: "Clearance Status", type: "text", placeholder: "Example: Awaiting documents" }
    ]
  };

  const HOSPITALITY_ROOM_FIELD_SET = {
    valueLabel: "Rate per Night",
    statusOptions: ["available", "occupied", "reserved", "maintenance", "inactive"],
    fields: [
      { id: "room_type", label: "Room / Unit Type", type: "text", placeholder: "Example: Single, Double, Suite" },
      { id: "capacity", label: "Guest Capacity", type: "number", placeholder: "Example: 2" },
      { id: "amenities", label: "Amenities", type: "text", placeholder: "Example: WiFi, AC, Breakfast included" },
      { id: "floor_location", label: "Floor / Location", type: "text", placeholder: "Example: 2nd Floor, Garden Wing" }
    ]
  };

  const HOSPITALITY_FNB_FIELD_SET = {
    valueLabel: "Unit Price",
    statusOptions: ["available", "low stock", "out of stock", "discontinued"],
    fields: [
      { id: "category", label: "Category", type: "text", placeholder: "Example: Main Course, Drink, Equipment" },
      { id: "stock_quantity", label: "Stock Quantity", type: "number", placeholder: "Example: 25" },
      { id: "reorder_level", label: "Reorder Level", type: "number", placeholder: "Example: 5" },
      { id: "supplier", label: "Supplier", type: "text", placeholder: "Example: Fresh Foods Ltd" }
    ]
  };

  const RETAIL_EXPIRY_FIELD_SET = {
    valueLabel: "Cost Price",
    statusOptions: ["in stock", "low stock", "out of stock", "expired", "discontinued"],
    fields: [
      { id: "expiry_date", label: "Expiry Date", type: "date" },
      { id: "batch_number", label: "Batch Number", type: "text", placeholder: "Example: B20260614" },
      { id: "stock_quantity", label: "Stock Quantity", type: "number", placeholder: "Example: 40" },
      { id: "reorder_level", label: "Reorder Level", type: "number", placeholder: "Example: 10" },
      { id: "supplier", label: "Supplier", type: "text", placeholder: "Example: MedSupply Kenya" }
    ]
  };

  const RETAIL_SERIAL_FIELD_SET = {
    valueLabel: "Cost Price",
    statusOptions: ["in stock", "low stock", "out of stock", "discontinued"],
    fields: [
      { id: "serial_number", label: "Serial Number / IMEI", type: "text", placeholder: "Example: 356789104561234" },
      { id: "warranty_expiry", label: "Warranty Expiry", type: "date" },
      { id: "stock_quantity", label: "Stock Quantity", type: "number", placeholder: "Example: 15" },
      { id: "supplier", label: "Supplier", type: "text" }
    ]
  };

  const RETAIL_VARIANT_FIELD_SET = {
    valueLabel: "Cost Price",
    statusOptions: ["in stock", "low stock", "out of stock", "discontinued"],
    fields: [
      { id: "size", label: "Size", type: "text", placeholder: "Example: M, 42, UK 8" },
      { id: "color", label: "Color", type: "text", placeholder: "Example: Navy Blue" },
      { id: "stock_quantity", label: "Stock Quantity", type: "number", placeholder: "Example: 20" },
      { id: "supplier", label: "Supplier", type: "text" }
    ]
  };

  const RETAIL_FURNITURE_FIELD_SET = {
    valueLabel: "Cost Price",
    statusOptions: ["in stock", "low stock", "out of stock", "discontinued"],
    fields: [
      { id: "dimensions", label: "Dimensions", type: "text", placeholder: "Example: 180cm x 90cm x 75cm" },
      { id: "material", label: "Material", type: "text", placeholder: "Example: Oak, Steel, Fabric" },
      { id: "stock_quantity", label: "Stock Quantity", type: "number", placeholder: "Example: 6" },
      { id: "supplier", label: "Supplier", type: "text" }
    ]
  };

  const RETAIL_BOOK_FIELD_SET = {
    valueLabel: "Cost Price",
    statusOptions: ["in stock", "low stock", "out of stock", "discontinued"],
    fields: [
      { id: "isbn", label: "ISBN", type: "text", placeholder: "Example: 978-3-16-148410-0" },
      { id: "author", label: "Author", type: "text" },
      { id: "stock_quantity", label: "Stock Quantity", type: "number", placeholder: "Example: 12" },
      { id: "supplier", label: "Supplier", type: "text" }
    ]
  };

  const RETAIL_GENERIC_FIELD_SET = {
    valueLabel: "Cost Price",
    statusOptions: ["in stock", "low stock", "out of stock", "discontinued"],
    fields: [
      { id: "sku", label: "SKU", type: "text", placeholder: "Example: SKU-00123" },
      { id: "stock_quantity", label: "Stock Quantity", type: "number", placeholder: "Example: 50" },
      { id: "reorder_level", label: "Reorder Level", type: "number", placeholder: "Example: 10" },
      { id: "supplier", label: "Supplier", type: "text" }
    ]
  };

  const ITEM_FIELD_SETS = {
    real_estate: REAL_ESTATE_ITEM_FIELD_SET,

    transport: LOGISTICS_TRANSPORT_FIELD_SET,
    cold_chain: LOGISTICS_COLD_CHAIN_FIELD_SET,
    clearing_forwarding: LOGISTICS_CLEARING_FIELD_SET,

    hotel: HOSPITALITY_ROOM_FIELD_SET,
    guest_house: HOSPITALITY_ROOM_FIELD_SET,
    lodge: HOSPITALITY_ROOM_FIELD_SET,
    resort: HOSPITALITY_ROOM_FIELD_SET,
    hostel: HOSPITALITY_ROOM_FIELD_SET,
    airbnb: HOSPITALITY_ROOM_FIELD_SET,
    restaurant: HOSPITALITY_FNB_FIELD_SET,
    bar_lounge: HOSPITALITY_FNB_FIELD_SET,
    catering: HOSPITALITY_FNB_FIELD_SET,

    pharmacy: RETAIL_EXPIRY_FIELD_SET,
    agrovet: RETAIL_EXPIRY_FIELD_SET,
    cosmetics: RETAIL_EXPIRY_FIELD_SET,
    electronics: RETAIL_SERIAL_FIELD_SET,
    mobile_phones: RETAIL_SERIAL_FIELD_SET,
    fashion: RETAIL_VARIANT_FIELD_SET,
    furniture_retail: RETAIL_FURNITURE_FIELD_SET,
    bookshop: RETAIL_BOOK_FIELD_SET,
    supermarket: RETAIL_GENERIC_FIELD_SET,
    hardware: RETAIL_GENERIC_FIELD_SET,
    general_retail: RETAIL_GENERIC_FIELD_SET
  };

  // Resolves which field-set a tenant's item form/card should use: the
  // matched section's own set (by section key) if the item's current
  // section has one, else the top-level business type's set (by type
  // key - currently only real_estate, since it has no section split),
  // else the generic minimal fallback for anything not authored yet.
  function resolveItemFieldSet(tenant, sectionLabel) {
    const type = resolve(tenant);

    if (type && type.sections && type.sections.length && sectionLabel) {
      const cleanLabel = String(sectionLabel || "").trim().toLowerCase();

      const section = type.sections.filter(function (candidate) {
        return String(candidate.label || "").toLowerCase() === cleanLabel;
      })[0];

      if (section && ITEM_FIELD_SETS[section.key]) {
        return ITEM_FIELD_SETS[section.key];
      }
    }

    if (type && ITEM_FIELD_SETS[type.key]) {
      return ITEM_FIELD_SETS[type.key];
    }

    return GENERIC_ITEM_FIELD_SET;
  }

  window.UnganiBusinessConfig = {
    TYPES,
    GENERAL,
    resolve,
    resolveWithSections,
    mergeWithGeneral,
    getRawBusinessText,
    getValue,
    unique,
    resolveItemFieldSet
  };
})();
