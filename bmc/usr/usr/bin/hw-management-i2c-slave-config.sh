# configuration
# read-only EEPROM on i2c bus 3 with slave id 0x4f. 0x1000 is the address
# range of the i2c slave backend subsystem. Hence the final address is 0x104f
I2C_SLAVE_TYPE_RO=slave-24c512ro
I2C_BUS_RO=3
I2C_RO_SLAVE_ADDRESS=4f

# BMC Control functions like factory reset, reboot are under slave address 0x45 on bus 3
I2C_RW_SLAVE_TYPE=slave-24c02
I2C_BUS_RW=3
I2C_RW_SLAVE_ADDRESS=45

# sys bus
I2C_NEW_DEV_PATH=/sys/bus/i2c/devices/i2c-$I2C_BUS_RO/new_device
I2C_SLAVE_FILE=/sys/bus/i2c/devices/i2c-$I2C_BUS_RO/$I2C_BUS_RO-10$I2C_RO_SLAVE_ADDRESS/name
I2C_SLAVE_MEM_FILE=/sys/bus/i2c/devices/$I2C_BUS_RO-10$I2C_RO_SLAVE_ADDRESS/slave-eeprom
I2C_NEW_DEV_PATH_CONTROL=/sys/bus/i2c/devices/i2c-$I2C_BUS_RW/new_device
I2C_SLAVE_FILE_CONTROL=/sys/bus/i2c/devices/i2c-$I2C_BUS_RW/$I2C_BUS_RW-10$I2C_RW_SLAVE_ADDRESS/name
I2C_SLAVE_MEM_FILE_CONTROL=/sys/bus/i2c/devices/$I2C_BUS_RW-10$I2C_RW_SLAVE_ADDRESS/slave-eeprom

