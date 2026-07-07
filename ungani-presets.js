(function () {
  const GENERAL = {
    key: "general",
    name: "General Business Operations",
    dashboardTitle: "Business Operations Dashboard",
    chartsTitle: "Business Analytics",
    itemsLabel: "Items / Assets / Stock",
    peopleLabel: "People / Contacts",
    tasksLabel: "Tasks / Follow-ups",
    recordsLabel: "Business Records",
    calendarLabel: "Calendar Activities",
    documentsLabel: "Documents",
    incomeCategories: [
      "Sales Income",
      "Service Income",
      "Customer Payment",
      "Deposit",
      "Other Income"
    ],
    expenseCategories: [
      "Staff Wages",
      "Supplies",
      "Transport",
      "Marketing / Advertising",
      "Rent",
      "Utilities",
      "Maintenance / Repairs",
      "Other Expense"
    ],
    itemTypes: [
      "Stock Item",
      "Asset",
      "Equipment",
      "Service",
      "Project",
      "Other"
    ],
    peopleTypes: [
      "Owner",
      "Manager",
      "Staff",
      "Client",
      "Customer",
      "Supplier",
      "Lead",
      "Contact"
    ],
    taskTypes: [
      "Follow-up",
      "Payment Reminder",
      "Document Collection",
      "Delivery",
      "Maintenance",
      "Meeting",
      "General Task"
    ],
    recordTypes: [
      "Daily Update",
      "Client Update",
      "Payment Note",
      "Work Progress",
      "Issue Log",
      "General Record"
    ],
    documentTypes: [
      "Agreement",
      "Receipt",
      "Invoice",
      "Business Document",
      "Staff Document",
      "Client Document",
      "Other Document"
    ],
    calendarTypes: [
      "Meeting",
      "Follow-up",
      "Payment Reminder",
      "Delivery",
      "Appointment",
      "Task Deadline",
      "Other Event"
    ],
    reportSections: [
      "Money Summary",
      "Tasks Summary",
      "Records Summary",
      "Items / Assets Summary",
      "People Summary",
      "Documents Summary",
      "Support Summary"
    ]
  };

  const PRESETS = [
    {
      key: "logistics",
      name: "Logistics & Transport",
      match: ["logistics", "transport", "fleet", "trip", "trips", "cold chain", "reefer", "genset", "clearing", "forwarding"],
      dashboardTitle: "Logistics Operations Dashboard",
      chartsTitle: "Logistics Analytics",
      itemsLabel: "Fleet / Trips / Assets",
      peopleLabel: "Drivers / Clients",
      tasksLabel: "Trip Tasks / Follow-ups",
      recordsLabel: "Operations Records",
      calendarLabel: "Trips / Follow-ups",
      documentsLabel: "Fleet / Client Documents",
      incomeCategories: [
        "Transport Income",
        "Trip Payment",
        "Client Payment",
        "Clearing / Forwarding Fee",
        "Cold Chain Service Fee",
        "Equipment Hire Income",
        "Other Logistics Income"
      ],
      expenseCategories: [
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
      itemTypes: [
        "Truck",
        "Vehicle",
        "Genset",
        "Reefer",
        "Trip",
        "Container",
        "Asset",
        "Spare Part"
      ],
      peopleTypes: [
        "Driver",
        "Client",
        "Customer",
        "Supplier",
        "Mechanic",
        "Supervisor",
        "Staff",
        "Contact"
      ],
      taskTypes: [
        "Trip Follow-up",
        "Driver Follow-up",
        "Client Update",
        "Maintenance Reminder",
        "Document Collection",
        "Payment Reminder",
        "Delivery Confirmation"
      ],
      recordTypes: [
        "Trip Update",
        "Fleet Update",
        "Driver Report",
        "Client Update",
        "Maintenance Record",
        "Fuel Record",
        "Incident Log"
      ],
      documentTypes: [
        "Delivery Note",
        "Invoice",
        "Receipt",
        "Vehicle Document",
        "Insurance Document",
        "Client Agreement",
        "Trip Document"
      ],
      calendarTypes: [
        "Trip Date",
        "Delivery Date",
        "Vehicle Service",
        "Client Meeting",
        "Payment Reminder",
        "Document Deadline"
      ]
    },
    {
      key: "real_estate",
      name: "Real Estate / Property Management",
      match: ["real estate", "property", "properties", "housing", "land", "rental"],
      dashboardTitle: "Property Operations Dashboard",
      chartsTitle: "Property Analytics",
      itemsLabel: "Properties / Listings",
      peopleLabel: "Agents / Leads",
      tasksLabel: "Property Tasks / Follow-ups",
      recordsLabel: "Property Records",
      calendarLabel: "Viewings / Site Visits",
      documentsLabel: "Property Documents",
      incomeCategories: [
        "Property Sale",
        "Rental Income",
        "Booking Deposit",
        "Agency / Service Fee",
        "Management Fee",
        "Other Property Income"
      ],
      expenseCategories: [
        "Agent Commission",
        "Marketing / Advertising",
        "Legal / Documentation Fees",
        "Property Maintenance",
        "Site Visit / Transport Cost",
        "Project Material Cost",
        "Staff Wages",
        "Other Real Estate Cost"
      ],
      itemTypes: [
        "Apartment",
        "House",
        "Villa",
        "Land",
        "Commercial Unit",
        "Rental Unit",
        "Project / Development"
      ],
      peopleTypes: [
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
      taskTypes: [
        "Lead Follow-up",
        "Viewing Schedule",
        "Document Collection",
        "Payment Reminder",
        "Agent Follow-up",
        "Maintenance Follow-up",
        "Project Update"
      ],
      recordTypes: [
        "Lead Inquiry",
        "Viewing Note",
        "Sale Update",
        "Rental Update",
        "Project Update",
        "Maintenance Note",
        "Client Update"
      ],
      documentTypes: [
        "Sale Agreement",
        "Lease Agreement",
        "Title Document",
        "Receipt",
        "Invoice",
        "Client ID",
        "Project Document"
      ],
      calendarTypes: [
        "Viewing",
        "Site Visit",
        "Payment Reminder",
        "Document Deadline",
        "Client Meeting",
        "Agent Follow-up"
      ]
    },
    {
      key: "salon",
      name: "Salon / Barber / Spa / Beauty",
      match: ["salon", "barber", "spa", "beauty"],
      dashboardTitle: "Salon Operations Dashboard",
      chartsTitle: "Salon Analytics",
      itemsLabel: "Services / Products",
      peopleLabel: "Staff / Clients",
      tasksLabel: "Appointments / Follow-ups",
      recordsLabel: "Client / Service Records",
      calendarLabel: "Appointments",
      documentsLabel: "Salon Documents",
      incomeCategories: [
        "Service Income",
        "Product Sale",
        "Appointment Deposit",
        "Membership / Package",
        "Other Salon Income"
      ],
      expenseCategories: [
        "Beauty Products",
        "Staff Wages",
        "Rent",
        "Utilities",
        "Equipment Maintenance",
        "Marketing / Advertising",
        "Other Salon Expense"
      ],
      itemTypes: [
        "Service",
        "Product",
        "Equipment",
        "Package",
        "Appointment",
        "Stock Item"
      ],
      peopleTypes: [
        "Stylist",
        "Barber",
        "Therapist",
        "Staff",
        "Client",
        "Customer",
        "Supplier"
      ],
      taskTypes: [
        "Appointment Follow-up",
        "Client Reminder",
        "Product Restock",
        "Payment Follow-up",
        "Staff Task",
        "Cleaning Task"
      ],
      recordTypes: [
        "Client Visit",
        "Service Note",
        "Product Sale",
        "Appointment Note",
        "Complaint / Feedback",
        "Daily Update"
      ],
      documentTypes: [
        "Receipt",
        "Invoice",
        "Supplier Document",
        "Staff Document",
        "Business Document"
      ],
      calendarTypes: [
        "Appointment",
        "Client Follow-up",
        "Staff Shift",
        "Product Restock",
        "Payment Reminder"
      ]
    },
    {
      key: "car_wash",
      name: "Car Wash / Auto Detailing",
      match: ["car wash", "auto detailing", "detailing"],
      dashboardTitle: "Car Wash Operations Dashboard",
      chartsTitle: "Car Wash Analytics",
      itemsLabel: "Services / Equipment",
      peopleLabel: "Staff / Customers",
      tasksLabel: "Bookings / Service Tasks",
      recordsLabel: "Service Records",
      calendarLabel: "Bookings / Services",
      documentsLabel: "Car Wash Documents",
      incomeCategories: [
        "Car Wash Service",
        "Detailing Service",
        "Customer Payment",
        "Package Payment",
        "Other Car Wash Income"
      ],
      expenseCategories: [
        "Cleaning Supplies",
        "Water",
        "Electricity",
        "Staff Wages",
        "Equipment Maintenance",
        "Marketing / Advertising",
        "Other Car Wash Expense"
      ],
      itemTypes: [
        "Service",
        "Equipment",
        "Cleaning Product",
        "Package",
        "Booking"
      ],
      peopleTypes: [
        "Washer",
        "Detailer",
        "Manager",
        "Staff",
        "Customer",
        "Supplier"
      ],
      taskTypes: [
        "Customer Booking",
        "Service Follow-up",
        "Equipment Maintenance",
        "Product Restock",
        "Payment Follow-up",
        "Cleaning Task"
      ],
      recordTypes: [
        "Service Record",
        "Customer Feedback",
        "Daily Sales Note",
        "Equipment Note",
        "Incident Log"
      ],
      documentTypes: [
        "Receipt",
        "Invoice",
        "Supplier Document",
        "Equipment Document",
        "Business Document"
      ],
      calendarTypes: [
        "Booking",
        "Service Appointment",
        "Equipment Service",
        "Customer Follow-up",
        "Payment Reminder"
      ]
    },
    {
      key: "printing",
      name: "Printing / Branding Company",
      match: ["printing", "branding", "print", "design"],
      dashboardTitle: "Printing Operations Dashboard",
      chartsTitle: "Printing Analytics",
      itemsLabel: "Jobs / Orders / Materials",
      peopleLabel: "Staff / Clients",
      tasksLabel: "Print Job Tasks",
      recordsLabel: "Job Records",
      calendarLabel: "Jobs / Delivery Dates",
      documentsLabel: "Job Documents",
      incomeCategories: [
        "Print Job Payment",
        "Branding Job Payment",
        "Design Fee",
        "Deposit",
        "Delivery Fee",
        "Other Printing Income"
      ],
      expenseCategories: [
        "Printing Materials",
        "Ink / Toner",
        "Paper / Media",
        "Machine Maintenance",
        "Staff Wages",
        "Transport / Delivery",
        "Other Printing Expense"
      ],
      itemTypes: [
        "Print Job",
        "Branding Job",
        "Material",
        "Machine",
        "Design Project",
        "Order"
      ],
      peopleTypes: [
        "Designer",
        "Printer",
        "Staff",
        "Client",
        "Customer",
        "Supplier"
      ],
      taskTypes: [
        "Design Task",
        "Print Task",
        "Client Approval",
        "Delivery Follow-up",
        "Payment Reminder",
        "Material Restock"
      ],
      recordTypes: [
        "Job Update",
        "Client Approval",
        "Design Note",
        "Print Note",
        "Delivery Note",
        "Complaint / Revision"
      ],
      documentTypes: [
        "Quotation",
        "Invoice",
        "Receipt",
        "Artwork File",
        "Client Approval",
        "Delivery Note"
      ],
      calendarTypes: [
        "Job Deadline",
        "Delivery Date",
        "Client Approval Date",
        "Payment Reminder",
        "Material Restock"
      ]
    },
    {
      key: "retail",
      name: "Retail Shop / Mini Market / Boutique",
      match: ["retail", "mini market", "shop", "store", "boutique", "fashion", "clothing", "apparel"],
      dashboardTitle: "Retail Operations Dashboard",
      chartsTitle: "Retail Analytics",
      itemsLabel: "Stock / Products",
      peopleLabel: "Staff / Customers",
      tasksLabel: "Stock / Sales Tasks",
      recordsLabel: "Sales / Stock Records",
      calendarLabel: "Sales / Restock Activity",
      documentsLabel: "Retail Documents",
      incomeCategories: [
        "Product Sale",
        "Customer Payment",
        "Bulk Sale",
        "Online Sale",
        "Other Retail Income"
      ],
      expenseCategories: [
        "Stock Purchase",
        "Supplier Payment",
        "Staff Wages",
        "Rent",
        "Transport",
        "Packaging",
        "Marketing / Advertising",
        "Other Retail Expense"
      ],
      itemTypes: [
        "Product",
        "Stock Item",
        "Asset",
        "Supplier Item",
        "Bundle"
      ],
      peopleTypes: [
        "Staff",
        "Customer",
        "Supplier",
        "Manager",
        "Sales Person",
        "Lead"
      ],
      taskTypes: [
        "Restock Reminder",
        "Supplier Follow-up",
        "Customer Follow-up",
        "Payment Reminder",
        "Stock Count",
        "Delivery Follow-up"
      ],
      recordTypes: [
        "Sales Note",
        "Stock Update",
        "Supplier Update",
        "Customer Request",
        "Daily Update",
        "Damaged Stock"
      ],
      documentTypes: [
        "Receipt",
        "Invoice",
        "Supplier Invoice",
        "Stock List",
        "Delivery Note",
        "Business Document"
      ],
      calendarTypes: [
        "Restock Date",
        "Supplier Follow-up",
        "Delivery Date",
        "Payment Reminder",
        "Stock Count"
      ]
    },
    {
      key: "pharmacy",
      name: "Pharmacy",
      match: ["pharmacy", "chemist", "medicine"],
      dashboardTitle: "Pharmacy Operations Dashboard",
      chartsTitle: "Pharmacy Analytics",
      itemsLabel: "Medicines / Stock",
      peopleLabel: "Staff / Suppliers",
      tasksLabel: "Pharmacy Tasks",
      recordsLabel: "Stock / Sales Records",
      calendarLabel: "Restock / Follow-ups",
      documentsLabel: "Pharmacy Documents",
      incomeCategories: [
        "Medicine Sale",
        "Customer Payment",
        "Prescription Sale",
        "Other Pharmacy Income"
      ],
      expenseCategories: [
        "Medicine Purchase",
        "Supplier Payment",
        "Staff Wages",
        "Rent",
        "Utilities",
        "Licensing",
        "Expired Stock Loss",
        "Other Pharmacy Expense"
      ],
      itemTypes: [
        "Medicine",
        "Medical Supply",
        "Stock Item",
        "Equipment",
        "Supplier Item"
      ],
      peopleTypes: [
        "Pharmacist",
        "Staff",
        "Supplier",
        "Customer",
        "Doctor / Referral",
        "Manager"
      ],
      taskTypes: [
        "Restock Reminder",
        "Expiry Check",
        "Supplier Follow-up",
        "Payment Reminder",
        "Stock Count",
        "Customer Follow-up"
      ],
      recordTypes: [
        "Stock Update",
        "Sales Note",
        "Expired Stock",
        "Supplier Update",
        "Customer Request",
        "Daily Update"
      ],
      documentTypes: [
        "Receipt",
        "Invoice",
        "Supplier Invoice",
        "License",
        "Stock List",
        "Business Document"
      ],
      calendarTypes: [
        "Restock Date",
        "Expiry Check",
        "Supplier Follow-up",
        "Payment Reminder",
        "Stock Count"
      ]
    },
    {
      key: "gym",
      name: "Gym / Fitness Center",
      match: ["gym", "fitness", "wellness"],
      dashboardTitle: "Gym Operations Dashboard",
      chartsTitle: "Gym Analytics",
      itemsLabel: "Services / Equipment",
      peopleLabel: "Trainers / Members",
      tasksLabel: "Membership / Service Tasks",
      recordsLabel: "Member / Service Records",
      calendarLabel: "Sessions / Renewals",
      documentsLabel: "Gym Documents",
      incomeCategories: [
        "Membership Payment",
        "Training Session Fee",
        "Package Payment",
        "Product Sale",
        "Other Gym Income"
      ],
      expenseCategories: [
        "Trainer Payment",
        "Equipment Maintenance",
        "Rent",
        "Utilities",
        "Cleaning",
        "Marketing / Advertising",
        "Other Gym Expense"
      ],
      itemTypes: [
        "Membership Package",
        "Training Service",
        "Equipment",
        "Product",
        "Class"
      ],
      peopleTypes: [
        "Trainer",
        "Staff",
        "Member",
        "Client",
        "Customer",
        "Supplier"
      ],
      taskTypes: [
        "Membership Renewal",
        "Client Follow-up",
        "Training Session",
        "Equipment Maintenance",
        "Payment Reminder",
        "Class Schedule"
      ],
      recordTypes: [
        "Member Update",
        "Training Note",
        "Payment Note",
        "Equipment Note",
        "Daily Update"
      ],
      documentTypes: [
        "Membership Form",
        "Receipt",
        "Invoice",
        "Staff Document",
        "Business Document"
      ],
      calendarTypes: [
        "Training Session",
        "Membership Renewal",
        "Class",
        "Payment Reminder",
        "Equipment Service"
      ]
    },
    {
      key: "warehouse",
      name: "Warehouse & Storage",
      match: ["warehouse", "storage"],
      dashboardTitle: "Warehouse Operations Dashboard",
      chartsTitle: "Warehouse Analytics",
      itemsLabel: "Storage / Stock / Assets",
      peopleLabel: "Staff / Clients",
      tasksLabel: "Warehouse Tasks",
      recordsLabel: "Storage / Stock Records",
      calendarLabel: "Dispatch / Storage Activity",
      documentsLabel: "Warehouse Documents",
      incomeCategories: [
        "Storage Fee",
        "Handling Fee",
        "Client Payment",
        "Dispatch Fee",
        "Other Warehouse Income"
      ],
      expenseCategories: [
        "Staff Wages",
        "Equipment Maintenance",
        "Rent",
        "Utilities",
        "Security",
        "Transport",
        "Other Warehouse Expense"
      ],
      itemTypes: [
        "Stock Item",
        "Storage Unit",
        "Pallet",
        "Asset",
        "Equipment",
        "Dispatch"
      ],
      peopleTypes: [
        "Warehouse Staff",
        "Manager",
        "Client",
        "Customer",
        "Supplier",
        "Driver"
      ],
      taskTypes: [
        "Stock Count",
        "Dispatch Follow-up",
        "Client Update",
        "Equipment Maintenance",
        "Payment Reminder",
        "Receiving Task"
      ],
      recordTypes: [
        "Stock Update",
        "Dispatch Note",
        "Receiving Note",
        "Client Update",
        "Damage Report",
        "Daily Update"
      ],
      documentTypes: [
        "Delivery Note",
        "Stock Sheet",
        "Invoice",
        "Receipt",
        "Client Agreement",
        "Warehouse Document"
      ],
      calendarTypes: [
        "Dispatch Date",
        "Receiving Date",
        "Stock Count",
        "Client Follow-up",
        "Payment Reminder"
      ]
    },
    {
      key: "security",
      name: "Security / Guarding Company",
      match: ["security", "guarding", "guards"],
      dashboardTitle: "Security Operations Dashboard",
      chartsTitle: "Security Analytics",
      itemsLabel: "Sites / Shifts / Equipment",
      peopleLabel: "Guards / Clients",
      tasksLabel: "Security Tasks",
      recordsLabel: "Site / Shift Records",
      calendarLabel: "Shifts / Site Visits",
      documentsLabel: "Security Documents",
      incomeCategories: [
        "Client Payment",
        "Security Service Fee",
        "Contract Payment",
        "Other Security Income"
      ],
      expenseCategories: [
        "Guard Wages",
        "Uniforms",
        "Transport",
        "Equipment",
        "Training",
        "Communication",
        "Other Security Expense"
      ],
      itemTypes: [
        "Site",
        "Shift",
        "Equipment",
        "Uniform",
        "Patrol Record"
      ],
      peopleTypes: [
        "Guard",
        "Supervisor",
        "Manager",
        "Client",
        "Customer",
        "Staff"
      ],
      taskTypes: [
        "Shift Assignment",
        "Site Follow-up",
        "Incident Follow-up",
        "Client Update",
        "Payment Reminder",
        "Equipment Check"
      ],
      recordTypes: [
        "Shift Report",
        "Incident Report",
        "Site Update",
        "Client Update",
        "Attendance Record",
        "Daily Update"
      ],
      documentTypes: [
        "Contract",
        "Invoice",
        "Receipt",
        "Guard Document",
        "Incident Report",
        "Client Document"
      ],
      calendarTypes: [
        "Shift",
        "Site Visit",
        "Client Meeting",
        "Payment Reminder",
        "Training"
      ]
    },
    {
      key: "cleaning",
      name: "Cleaning / Facility Services",
      match: ["cleaning", "facility", "facilities"],
      dashboardTitle: "Cleaning Operations Dashboard",
      chartsTitle: "Cleaning Analytics",
      itemsLabel: "Jobs / Sites / Supplies",
      peopleLabel: "Staff / Clients",
      tasksLabel: "Cleaning Tasks",
      recordsLabel: "Job / Site Records",
      calendarLabel: "Cleaning Schedule",
      documentsLabel: "Cleaning Documents",
      incomeCategories: [
        "Cleaning Service Fee",
        "Client Payment",
        "Contract Payment",
        "Other Cleaning Income"
      ],
      expenseCategories: [
        "Cleaning Supplies",
        "Staff Wages",
        "Transport",
        "Equipment Maintenance",
        "Uniforms",
        "Other Cleaning Expense"
      ],
      itemTypes: [
        "Cleaning Job",
        "Site",
        "Supply",
        "Equipment",
        "Contract"
      ],
      peopleTypes: [
        "Cleaner",
        "Supervisor",
        "Staff",
        "Client",
        "Customer",
        "Supplier"
      ],
      taskTypes: [
        "Cleaning Job",
        "Site Follow-up",
        "Supply Restock",
        "Client Update",
        "Payment Reminder",
        "Equipment Check"
      ],
      recordTypes: [
        "Job Update",
        "Site Report",
        "Client Feedback",
        "Supply Note",
        "Daily Update",
        "Issue Log"
      ],
      documentTypes: [
        "Contract",
        "Invoice",
        "Receipt",
        "Client Document",
        "Staff Document"
      ],
      calendarTypes: [
        "Cleaning Schedule",
        "Site Visit",
        "Client Follow-up",
        "Payment Reminder",
        "Supply Restock"
      ]
    },
    {
      key: "construction",
      name: "Construction / Contractors",
      match: ["construction", "contractor", "contractors", "building"],
      dashboardTitle: "Construction Operations Dashboard",
      chartsTitle: "Construction Analytics",
      itemsLabel: "Projects / Materials / Assets",
      peopleLabel: "Workers / Clients",
      tasksLabel: "Construction Tasks",
      recordsLabel: "Project Records",
      calendarLabel: "Project Schedule",
      documentsLabel: "Construction Documents",
      incomeCategories: [
        "Project Payment",
        "Client Deposit",
        "Contract Payment",
        "Service Fee",
        "Other Construction Income"
      ],
      expenseCategories: [
        "Materials",
        "Labour",
        "Transport",
        "Equipment Hire",
        "Subcontractor Payment",
        "Site Expenses",
        "Other Construction Expense"
      ],
      itemTypes: [
        "Project",
        "Material",
        "Asset",
        "Equipment",
        "Site",
        "Work Package"
      ],
      peopleTypes: [
        "Worker",
        "Contractor",
        "Supplier",
        "Client",
        "Engineer",
        "Supervisor",
        "Staff"
      ],
      taskTypes: [
        "Project Task",
        "Material Follow-up",
        "Site Update",
        "Client Update",
        "Payment Reminder",
        "Inspection"
      ],
      recordTypes: [
        "Project Update",
        "Site Report",
        "Material Record",
        "Client Update",
        "Issue Log",
        "Daily Update"
      ],
      documentTypes: [
        "Contract",
        "Quotation",
        "Invoice",
        "Receipt",
        "Project Document",
        "Site Document"
      ],
      calendarTypes: [
        "Site Visit",
        "Inspection",
        "Project Deadline",
        "Material Delivery",
        "Payment Reminder"
      ]
    },
    {
      key: "clinic",
      name: "Clinic / Health Services",
      match: ["clinic", "health", "medical", "hospital"],
      dashboardTitle: "Clinic Operations Dashboard",
      chartsTitle: "Clinic Analytics",
      itemsLabel: "Supplies / Equipment",
      peopleLabel: "Staff / Patients",
      tasksLabel: "Clinic Tasks",
      recordsLabel: "Patient / Clinic Records",
      calendarLabel: "Appointments",
      documentsLabel: "Clinic Documents",
      incomeCategories: [
        "Consultation Fee",
        "Service Payment",
        "Medicine Sale",
        "Client Payment",
        "Other Clinic Income"
      ],
      expenseCategories: [
        "Medical Supplies",
        "Staff Wages",
        "Rent",
        "Utilities",
        "Equipment Maintenance",
        "Licensing",
        "Other Clinic Expense"
      ],
      itemTypes: [
        "Medical Supply",
        "Equipment",
        "Service",
        "Medicine",
        "Asset"
      ],
      peopleTypes: [
        "Doctor",
        "Nurse",
        "Staff",
        "Patient",
        "Client",
        "Supplier"
      ],
      taskTypes: [
        "Patient Follow-up",
        "Appointment",
        "Supply Restock",
        "Payment Reminder",
        "Equipment Maintenance",
        "Document Follow-up"
      ],
      recordTypes: [
        "Patient Visit",
        "Clinic Note",
        "Payment Note",
        "Supply Update",
        "Daily Update",
        "Issue Log"
      ],
      documentTypes: [
        "Receipt",
        "Invoice",
        "Patient Document",
        "Staff Document",
        "License",
        "Business Document"
      ],
      calendarTypes: [
        "Appointment",
        "Patient Follow-up",
        "Supply Restock",
        "Payment Reminder",
        "Equipment Service"
      ]
    },
    {
      key: "school",
      name: "School / Training Center",
      match: ["school", "training", "academy", "education"],
      dashboardTitle: "School Operations Dashboard",
      chartsTitle: "School Analytics",
      itemsLabel: "Classes / Assets / Materials",
      peopleLabel: "Staff / Learners",
      tasksLabel: "School Tasks",
      recordsLabel: "Learner / School Records",
      calendarLabel: "Classes / Training",
      documentsLabel: "School Documents",
      incomeCategories: [
        "School Fees",
        "Training Fee",
        "Registration Fee",
        "Material Fee",
        "Other School Income"
      ],
      expenseCategories: [
        "Staff Wages",
        "Learning Materials",
        "Rent",
        "Utilities",
        "Transport",
        "Equipment",
        "Other School Expense"
      ],
      itemTypes: [
        "Class",
        "Course",
        "Asset",
        "Learning Material",
        "Equipment"
      ],
      peopleTypes: [
        "Teacher",
        "Trainer",
        "Staff",
        "Learner",
        "Student",
        "Parent",
        "Supplier"
      ],
      taskTypes: [
        "Learner Follow-up",
        "Fee Reminder",
        "Class Task",
        "Document Collection",
        "Parent Follow-up",
        "Training Task"
      ],
      recordTypes: [
        "Learner Update",
        "Class Update",
        "Fee Note",
        "Parent Update",
        "Daily Update",
        "Issue Log"
      ],
      documentTypes: [
        "Receipt",
        "Invoice",
        "Learner Document",
        "Staff Document",
        "Training Material",
        "Business Document"
      ],
      calendarTypes: [
        "Class",
        "Training Session",
        "Fee Reminder",
        "Parent Meeting",
        "Exam / Assessment"
      ]
    },
    {
      key: "events",
      name: "Events / Catering",
      match: ["events", "catering", "caterer"],
      dashboardTitle: "Events Operations Dashboard",
      chartsTitle: "Events Analytics",
      itemsLabel: "Events / Orders / Equipment",
      peopleLabel: "Staff / Clients",
      tasksLabel: "Event Tasks",
      recordsLabel: "Event / Client Records",
      calendarLabel: "Event Schedule",
      documentsLabel: "Event Documents",
      incomeCategories: [
        "Event Payment",
        "Catering Payment",
        "Booking Deposit",
        "Service Fee",
        "Other Event Income"
      ],
      expenseCategories: [
        "Food Supplies",
        "Staff Wages",
        "Transport",
        "Equipment Hire",
        "Venue Cost",
        "Marketing / Advertising",
        "Other Event Expense"
      ],
      itemTypes: [
        "Event",
        "Order",
        "Equipment",
        "Package",
        "Service",
        "Booking"
      ],
      peopleTypes: [
        "Planner",
        "Chef",
        "Staff",
        "Client",
        "Customer",
        "Supplier"
      ],
      taskTypes: [
        "Event Preparation",
        "Client Follow-up",
        "Supplier Follow-up",
        "Payment Reminder",
        "Delivery Task",
        "Setup Task"
      ],
      recordTypes: [
        "Event Update",
        "Client Note",
        "Supplier Note",
        "Payment Note",
        "Delivery Note",
        "Issue Log"
      ],
      documentTypes: [
        "Quotation",
        "Invoice",
        "Receipt",
        "Client Agreement",
        "Supplier Document",
        "Event Document"
      ],
      calendarTypes: [
        "Event Date",
        "Setup Date",
        "Client Meeting",
        "Supplier Follow-up",
        "Payment Reminder"
      ]
    },
    {
      key: "repair",
      name: "Repair Shop",
      match: ["repair", "repairs", "maintenance shop"],
      dashboardTitle: "Repair Shop Operations Dashboard",
      chartsTitle: "Repair Shop Analytics",
      itemsLabel: "Repair Jobs / Spare Parts",
      peopleLabel: "Staff / Customers",
      tasksLabel: "Repair Tasks",
      recordsLabel: "Repair Records",
      calendarLabel: "Repair Schedule",
      documentsLabel: "Repair Documents",
      incomeCategories: [
        "Repair Service",
        "Spare Part Sale",
        "Customer Payment",
        "Deposit",
        "Other Repair Income"
      ],
      expenseCategories: [
        "Spare Parts",
        "Tools",
        "Staff Wages",
        "Rent",
        "Utilities",
        "Transport",
        "Other Repair Expense"
      ],
      itemTypes: [
        "Repair Job",
        "Spare Part",
        "Tool",
        "Equipment",
        "Customer Item"
      ],
      peopleTypes: [
        "Technician",
        "Staff",
        "Customer",
        "Client",
        "Supplier",
        "Manager"
      ],
      taskTypes: [
        "Repair Follow-up",
        "Customer Update",
        "Spare Part Follow-up",
        "Payment Reminder",
        "Testing Task",
        "Delivery Task"
      ],
      recordTypes: [
        "Repair Update",
        "Customer Note",
        "Spare Part Note",
        "Payment Note",
        "Issue Log",
        "Daily Update"
      ],
      documentTypes: [
        "Receipt",
        "Invoice",
        "Job Card",
        "Supplier Document",
        "Customer Document"
      ],
      calendarTypes: [
        "Repair Deadline",
        "Customer Pickup",
        "Supplier Follow-up",
        "Payment Reminder",
        "Testing Date"
      ]
    },
    {
      key: "photography",
      name: "Photography / Videography",
      match: ["photography", "videography", "photo", "video"],
      dashboardTitle: "Photography Operations Dashboard",
      chartsTitle: "Photography Analytics",
      itemsLabel: "Shoots / Projects / Equipment",
      peopleLabel: "Staff / Clients",
      tasksLabel: "Shoot / Project Tasks",
      recordsLabel: "Project Records",
      calendarLabel: "Shoot Schedule",
      documentsLabel: "Creative Documents",
      incomeCategories: [
        "Shoot Payment",
        "Editing Fee",
        "Booking Deposit",
        "Delivery Fee",
        "Other Creative Income"
      ],
      expenseCategories: [
        "Equipment",
        "Transport",
        "Assistant Payment",
        "Editing Cost",
        "Software",
        "Marketing / Advertising",
        "Other Creative Expense"
      ],
      itemTypes: [
        "Shoot",
        "Project",
        "Equipment",
        "Package",
        "Delivery"
      ],
      peopleTypes: [
        "Photographer",
        "Videographer",
        "Editor",
        "Staff",
        "Client",
        "Customer"
      ],
      taskTypes: [
        "Shoot Task",
        "Editing Task",
        "Client Approval",
        "Delivery Follow-up",
        "Payment Reminder",
        "Equipment Check"
      ],
      recordTypes: [
        "Shoot Note",
        "Editing Update",
        "Client Update",
        "Delivery Note",
        "Payment Note",
        "Issue Log"
      ],
      documentTypes: [
        "Quotation",
        "Invoice",
        "Receipt",
        "Client Agreement",
        "Delivery File",
        "Project Document"
      ],
      calendarTypes: [
        "Shoot Date",
        "Editing Deadline",
        "Delivery Date",
        "Client Meeting",
        "Payment Reminder"
      ]
    },
    {
      key: "car_hire",
      name: "Car Hire / Car Rental",
      match: ["car hire", "car rental", "rental car"],
      dashboardTitle: "Car Hire Operations Dashboard",
      chartsTitle: "Car Hire Analytics",
      itemsLabel: "Vehicles / Bookings",
      peopleLabel: "Drivers / Customers",
      tasksLabel: "Booking / Vehicle Tasks",
      recordsLabel: "Rental Records",
      calendarLabel: "Bookings / Vehicle Schedule",
      documentsLabel: "Vehicle / Rental Documents",
      incomeCategories: [
        "Rental Payment",
        "Booking Deposit",
        "Driver Fee",
        "Delivery Fee",
        "Other Car Hire Income"
      ],
      expenseCategories: [
        "Fuel",
        "Vehicle Maintenance",
        "Insurance",
        "Driver Payment",
        "Cleaning",
        "Licensing",
        "Other Car Hire Expense"
      ],
      itemTypes: [
        "Vehicle",
        "Booking",
        "Asset",
        "Service",
        "Maintenance Record"
      ],
      peopleTypes: [
        "Driver",
        "Staff",
        "Customer",
        "Client",
        "Supplier",
        "Mechanic"
      ],
      taskTypes: [
        "Booking Follow-up",
        "Vehicle Service",
        "Customer Follow-up",
        "Payment Reminder",
        "Document Collection",
        "Vehicle Return"
      ],
      recordTypes: [
        "Booking Update",
        "Vehicle Update",
        "Customer Note",
        "Maintenance Record",
        "Payment Note",
        "Incident Log"
      ],
      documentTypes: [
        "Rental Agreement",
        "Vehicle Document",
        "Insurance",
        "Receipt",
        "Invoice",
        "Client ID"
      ],
      calendarTypes: [
        "Booking Date",
        "Vehicle Return",
        "Vehicle Service",
        "Payment Reminder",
        "Client Follow-up"
      ]
    },
    {
      key: "furniture",
      name: "Furniture / Carpentry",
      match: ["furniture", "carpentry", "woodwork"],
      dashboardTitle: "Furniture Operations Dashboard",
      chartsTitle: "Furniture Analytics",
      itemsLabel: "Orders / Materials / Projects",
      peopleLabel: "Staff / Clients",
      tasksLabel: "Order / Workshop Tasks",
      recordsLabel: "Order Records",
      calendarLabel: "Order / Delivery Schedule",
      documentsLabel: "Furniture Documents",
      incomeCategories: [
        "Furniture Sale",
        "Custom Order Payment",
        "Deposit",
        "Delivery Fee",
        "Other Furniture Income"
      ],
      expenseCategories: [
        "Materials",
        "Labour",
        "Transport",
        "Tools",
        "Workshop Rent",
        "Machine Maintenance",
        "Other Furniture Expense"
      ],
      itemTypes: [
        "Order",
        "Furniture Item",
        "Material",
        "Project",
        "Tool",
        "Equipment"
      ],
      peopleTypes: [
        "Carpenter",
        "Designer",
        "Staff",
        "Client",
        "Customer",
        "Supplier"
      ],
      taskTypes: [
        "Order Task",
        "Material Follow-up",
        "Client Approval",
        "Delivery Follow-up",
        "Payment Reminder",
        "Workshop Task"
      ],
      recordTypes: [
        "Order Update",
        "Material Note",
        "Client Approval",
        "Delivery Note",
        "Payment Note",
        "Issue Log"
      ],
      documentTypes: [
        "Quotation",
        "Invoice",
        "Receipt",
        "Design Document",
        "Delivery Note",
        "Client Agreement"
      ],
      calendarTypes: [
        "Order Deadline",
        "Delivery Date",
        "Client Approval",
        "Material Delivery",
        "Payment Reminder"
      ]
    },
    {
      key: "agrovet",
      name: "Agrovet / Farm Supplies",
      match: ["agrovet", "farm", "farming", "agriculture"],
      dashboardTitle: "Agrovet Operations Dashboard",
      chartsTitle: "Agrovet Analytics",
      itemsLabel: "Farm Supplies / Stock",
      peopleLabel: "Staff / Suppliers",
      tasksLabel: "Stock / Supplier Tasks",
      recordsLabel: "Stock / Sales Records",
      calendarLabel: "Restock / Follow-ups",
      documentsLabel: "Agrovet Documents",
      incomeCategories: [
        "Product Sale",
        "Customer Payment",
        "Bulk Sale",
        "Other Agrovet Income"
      ],
      expenseCategories: [
        "Stock Purchase",
        "Supplier Payment",
        "Transport",
        "Staff Wages",
        "Rent",
        "Utilities",
        "Other Agrovet Expense"
      ],
      itemTypes: [
        "Farm Supply",
        "Stock Item",
        "Medicine",
        "Feed",
        "Equipment",
        "Supplier Item"
      ],
      peopleTypes: [
        "Staff",
        "Customer",
        "Supplier",
        "Farmer",
        "Manager",
        "Sales Person"
      ],
      taskTypes: [
        "Restock Reminder",
        "Supplier Follow-up",
        "Customer Follow-up",
        "Payment Reminder",
        "Stock Count",
        "Delivery Follow-up"
      ],
      recordTypes: [
        "Sales Note",
        "Stock Update",
        "Supplier Update",
        "Customer Request",
        "Daily Update",
        "Expired / Damaged Stock"
      ],
      documentTypes: [
        "Receipt",
        "Invoice",
        "Supplier Invoice",
        "Stock List",
        "Delivery Note",
        "Business Document"
      ],
      calendarTypes: [
        "Restock Date",
        "Supplier Follow-up",
        "Delivery Date",
        "Payment Reminder",
        "Stock Count"
      ]
    }
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

  function getPreset(tenant) {
    const raw = getRawBusinessText(tenant);

    for (let i = 0; i < PRESETS.length; i++) {
      const preset = PRESETS[i];

      for (let j = 0; j < preset.match.length; j++) {
        if (raw.includes(preset.match[j])) {
          return mergePreset(preset);
        }
      }
    }

    return mergePreset({});
  }

  function mergePreset(preset) {
    return Object.assign({}, GENERAL, preset, {
      incomeCategories: unique([...(preset.incomeCategories || []), ...GENERAL.incomeCategories]),
      expenseCategories: unique([...(preset.expenseCategories || []), ...GENERAL.expenseCategories]),
      itemTypes: unique([...(preset.itemTypes || []), ...GENERAL.itemTypes]),
      peopleTypes: unique([...(preset.peopleTypes || []), ...GENERAL.peopleTypes]),
      taskTypes: unique([...(preset.taskTypes || []), ...GENERAL.taskTypes]),
      recordTypes: unique([...(preset.recordTypes || []), ...GENERAL.recordTypes]),
      documentTypes: unique([...(preset.documentTypes || []), ...GENERAL.documentTypes]),
      calendarTypes: unique([...(preset.calendarTypes || []), ...GENERAL.calendarTypes]),
      reportSections: unique([...(preset.reportSections || []), ...GENERAL.reportSections])
    });
  }

  function unique(values) {
    const seen = {};
    const output = [];

    values.forEach(function (value) {
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

  function escapeHtml(value) {
    return String(value === null || value === undefined ? "" : value)
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;")
      .replace(/'/g, "&#039;");
  }

  function optionList(values, selectedValue) {
    const selected = String(selectedValue || "").toLowerCase();

    return (values || []).map(function (value) {
      const clean = String(value || "").trim();
      const isSelected = clean.toLowerCase() === selected ? "selected" : "";

      return `<option value="${escapeHtml(clean)}" ${isSelected}>${escapeHtml(clean)}</option>`;
    }).join("");
  }

  function datalist(id, values) {
    return `
      <datalist id="${escapeHtml(id)}">
        ${(values || []).map(function (value) {
          return `<option value="${escapeHtml(value)}"></option>`;
        }).join("")}
      </datalist>
    `;
  }

  function presetSummaryCards(preset) {
    return `
      <div class="ungani-grid">
        <div class="ungani-card">
          <h3>${escapeHtml(preset.itemsLabel)}</h3>
          <p class="ungani-small">${escapeHtml(preset.itemTypes.slice(0, 5).join(" · "))}</p>
        </div>

        <div class="ungani-card">
          <h3>${escapeHtml(preset.peopleLabel)}</h3>
          <p class="ungani-small">${escapeHtml(preset.peopleTypes.slice(0, 5).join(" · "))}</p>
        </div>

        <div class="ungani-card">
          <h3>${escapeHtml(preset.tasksLabel)}</h3>
          <p class="ungani-small">${escapeHtml(preset.taskTypes.slice(0, 5).join(" · "))}</p>
        </div>

        <div class="ungani-card">
          <h3>Money Categories</h3>
          <p class="ungani-small">${escapeHtml(preset.incomeCategories.slice(0, 3).join(" · "))}</p>
        </div>
      </div>
    `;
  }

  window.UnganiPresets = {
    GENERAL,
    PRESETS,
    getPreset,
    optionList,
    datalist,
    presetSummaryCards,
    escapeHtml
  };
})();
