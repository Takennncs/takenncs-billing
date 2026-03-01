# takenncs-billing
Advanced billing system for QBCore FiveM servers

## 📋 Features
- Create and manage invoices
- Real-time bill updates
- Job-based access control
- Tablet animation support
- Multi-language support (configurable)
- Automatic bill cleanup

## ✅ Requirements
- QBCore Framework
- oxmysql

## Database Setup
Main invoices table

```
CREATE TABLE IF NOT EXISTS `takenncs_billing_invoices` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `citizenid` varchar(50) NOT NULL,
  `name` varchar(100) NOT NULL,
  `amount` int(11) NOT NULL,
  `society` varchar(50) NOT NULL,
  `sender` varchar(100) NOT NULL,
  `sendercitizenid` varchar(50) NOT NULL,
  `description` varchar(255) NOT NULL,
  `society_label` varchar(100) NOT NULL,
  `days` bigint(20) NOT NULL,
  `status` varchar(20) DEFAULT 'pending',
  PRIMARY KEY (`id`),
  KEY `citizenid` (`citizenid`),
  KEY `status` (`status`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `bank_accounts_new` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `amount` int(11) NOT NULL DEFAULT 0,
  `auth` varchar(50) NOT NULL,
  `isFrozen` tinyint(1) NOT NULL DEFAULT 0,
  PRIMARY KEY (`id`),
  UNIQUE KEY `auth` (`auth`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

INSERT INTO `bank_accounts_new` (`auth`, `amount`, `isFrozen`) VALUES
('society_police', 0, 0),
('society_ambulance', 0, 0),
('society_mechanic', 0, 0),
('society_taxi', 0, 0),
('society_realestate', 0, 0),
('society_cardealer', 0, 0),
('society_wigwamburger', 0, 0),
('society_judge', 0, 0),
('society_lawyer', 0, 0);
```

## Server Exports
-- Bill an online player
```exports['takenncs-billing']:BillPlayer(sourceUserId, targetUserId, amount, description)```

-- Bill an offline player
```exports['takenncs-billing']:BillPlayerOffline(sourceUserId, targetCitizenId, amount, description)```

## Client Exports
-- Open billing menu
```exports['takenncs-billing']:OpenBillingMenu()```

-- Close billing menu
```exports['takenncs-billing']:CloseBillingMenu()```

## Money not going to society account
- Verify Config.MoneyToJobAccount is set to true
- Check if society account exists in bank_accounts_new table
- Society account name should be society_jobname (e.g., society_police)

## License
** This resource is for personal use only. Redistribution without permission is prohibited. **

__Created by takenncs__
