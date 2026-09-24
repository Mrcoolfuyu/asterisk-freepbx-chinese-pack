/*M!999999\- enable the sandbox mode */ 

/*!40101 SET @OLD_CHARACTER_SET_CLIENT=@@CHARACTER_SET_CLIENT */;
/*!40101 SET @OLD_CHARACTER_SET_RESULTS=@@CHARACTER_SET_RESULTS */;
/*!40101 SET @OLD_COLLATION_CONNECTION=@@COLLATION_CONNECTION */;
/*!40101 SET NAMES utf8mb4 */;
/*!40103 SET @OLD_TIME_ZONE=@@TIME_ZONE */;
/*!40103 SET TIME_ZONE='+00:00' */;
/*!40014 SET @OLD_FOREIGN_KEY_CHECKS=@@FOREIGN_KEY_CHECKS, FOREIGN_KEY_CHECKS=0 */;
/*!40101 SET @OLD_SQL_MODE=@@SQL_MODE, SQL_MODE='NO_AUTO_VALUE_ON_ZERO' */;
/*!40111 SET @OLD_SQL_NOTES=@@SQL_NOTES, SQL_NOTES=0 */;

LOCK TABLES `kvstore_FreePBX_modules_Hotelwakeup` WRITE;
/*!40000 ALTER TABLE `kvstore_FreePBX_modules_Hotelwakeup` DISABLE KEYS */;
INSERT INTO `kvstore_FreePBX_modules_Hotelwakeup` VALUES ('SayUnixTime','[\"pIM\"]','json-arr','message_zh_CN');
INSERT INTO `kvstore_FreePBX_modules_Hotelwakeup` VALUES ('welcome','[\"custom\\/hw-welcome\"]','json-arr','message_zh_CN');
INSERT INTO `kvstore_FreePBX_modules_Hotelwakeup` VALUES ('goodbye','[\"custom\\/hw-goodbye\"]','json-arr','message_zh_CN');
INSERT INTO `kvstore_FreePBX_modules_Hotelwakeup` VALUES ('error','[\"custom\\/hw-error\"]','json-arr','message_zh_CN');
INSERT INTO `kvstore_FreePBX_modules_Hotelwakeup` VALUES ('retry','[\"custom\\/hw-retry\"]','json-arr','message_zh_CN');
INSERT INTO `kvstore_FreePBX_modules_Hotelwakeup` VALUES ('optionInvalid','[\"custom\\/hw-invalid\"]','json-arr','message_zh_CN');
INSERT INTO `kvstore_FreePBX_modules_Hotelwakeup` VALUES ('invalidDialing','[\"custom\\/hw-invaliddial\"]','json-arr','message_zh_CN');
INSERT INTO `kvstore_FreePBX_modules_Hotelwakeup` VALUES ('operatorSelectExt','[\"custom\\/hw-opselect\"]','json-arr','message_zh_CN');
INSERT INTO `kvstore_FreePBX_modules_Hotelwakeup` VALUES ('operatorEntered','[\"custom\\/hw-opentered\",\"d|{number}\",\"silence|500\"]','json-arr','message_zh_CN');
INSERT INTO `kvstore_FreePBX_modules_Hotelwakeup` VALUES ('wakeupMenu','[\"custom\\/hw-menu1\",\"silence|400\",\"custom\\/hw-menu2\",\"silence|500\"]','json-arr','message_zh_CN');
INSERT INTO `kvstore_FreePBX_modules_Hotelwakeup` VALUES ('wakeupAdd','[\"custom\\/hw-add\"]','json-arr','message_zh_CN');
INSERT INTO `kvstore_FreePBX_modules_Hotelwakeup` VALUES ('wakeupAddType12H','[\"custom\\/hw-addtype1\",\"silence|300\",\"custom\\/hw-addtype2\"]','json-arr','message_zh_CN');
INSERT INTO `kvstore_FreePBX_modules_Hotelwakeup` VALUES ('wakeupAddOk','[\"custom\\/hw-addok\",\"SayUnixTime|{time}\",\"silence|500\"]','json-arr','message_zh_CN');
INSERT INTO `kvstore_FreePBX_modules_Hotelwakeup` VALUES ('wakeupList','[\"custom\\/hw-list-pre\",\"{count}\",\"custom\\/hw-list-post\",\"silence|500\"]','json-arr','message_zh_CN');
INSERT INTO `kvstore_FreePBX_modules_Hotelwakeup` VALUES ('wakeupListEmpty','[\"custom\\/hw-listempty\"]','json-arr','message_zh_CN');
INSERT INTO `kvstore_FreePBX_modules_Hotelwakeup` VALUES ('wakeupListInfoCall','[\"custom\\/hw-info-pre\",\"{number}\",\"custom\\/hw-info-mid\",\"SayUnixTime|{time}\",\"silence|500\"]','json-arr','message_zh_CN');
INSERT INTO `kvstore_FreePBX_modules_Hotelwakeup` VALUES ('wakeupListMenu','[\"custom\\/hw-lmenu1\",\"silence|400\",\"custom\\/hw-lmenu2\",\"silence|400\",\"custom\\/hw-lmenu3\",\"silence|500\"]','json-arr','message_zh_CN');
INSERT INTO `kvstore_FreePBX_modules_Hotelwakeup` VALUES ('wakeupListCancelCall','[\"custom\\/hw-cancelled\"]','json-arr','message_zh_CN');
INSERT INTO `kvstore_FreePBX_modules_Hotelwakeup` VALUES ('wakeConfirmMenu','[\"custom\\/hw-cmenu1\",\"silence|400\",\"custom\\/hw-cmenu2\",\"silence|400\",\"custom\\/hw-cmenu3\"]','json-arr','message_zh_CN');
INSERT INTO `kvstore_FreePBX_modules_Hotelwakeup` VALUES ('wakeConfirmDelay','[\"custom\\/hw-conf-pre\",\"{delay}\",\"custom\\/hw-conf-post\",\"silence|500\"]','json-arr','message_zh_CN');
/*!40000 ALTER TABLE `kvstore_FreePBX_modules_Hotelwakeup` ENABLE KEYS */;
UNLOCK TABLES;
/*!40103 SET TIME_ZONE=@OLD_TIME_ZONE */;

/*!40101 SET SQL_MODE=@OLD_SQL_MODE */;
/*!40014 SET FOREIGN_KEY_CHECKS=@OLD_FOREIGN_KEY_CHECKS */;
/*!40101 SET CHARACTER_SET_CLIENT=@OLD_CHARACTER_SET_CLIENT */;
/*!40101 SET CHARACTER_SET_RESULTS=@OLD_CHARACTER_SET_RESULTS */;
/*!40101 SET COLLATION_CONNECTION=@OLD_COLLATION_CONNECTION */;
/*!40111 SET SQL_NOTES=@OLD_SQL_NOTES */;

