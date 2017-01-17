/*
 * Copyright (C) Mellanox Technologies, Ltd. 2010-2015 ALL RIGHTS RESERVED.
 *
 * This software product is a proprietary product of Mellanox Technologies, Ltd.
 * (the "Company") and all right, title, and interest in and to the software product,
 * including all associated intellectual property rights, are and shall
 * remain exclusively with the Company.
 *
 * This software product is governed by the End User License Agreement
 * provided with the software product.
 *
 */

#ifndef SX_DEVICE_H
#define SX_DEVICE_H

#include <linux/types.h>
#include <linux/fs.h>
#include <linux/device.h>
#include <linux/cdev.h>
#include <linux/mlx_sx/kernel_user.h>

#ifndef SYSTEM_PCI
#define NO_PCI
#endif

/* According to CQe */
enum sx_packet_type {
	PKT_TYPE_IB_Raw		= 0,
	PKT_TYPE_IB_non_Raw	= 1,
	PKT_TYPE_ETH		= 2,
	PKT_TYPE_FC			= 3,
	PKT_TYPE_FCoIB		= 4,
	PKT_TYPE_FCoETH		= 5,
	PKT_TYPE_ETHoIB		= 6,
	PKT_TYPE_NUM
};

static const char *sx_cqe_packet_type_str[] = {
	"PKT_TYPE_IB_Raw",
	"PKT_TYPE_IB_non_Raw",
	"PKT_TYPE_ETH",
	"PKT_TYPE_FC",
	"PKT_TYPE_FCoIB",
	"PKT_TYPE_FCoETH",
	"PKT_TYPE_ETHoIB"
};

static const int sx_cqe_packet_type_str_len =
		sizeof(sx_cqe_packet_type_str)/sizeof(char *);

enum l2_type {
	L2_TYPE_DONT_CARE	= -1,
	L2_TYPE_IB			= 0,
	L2_TYPE_ETH			= 1,
	L2_TYPE_FC			= 2
};

enum sx_event {
	SX_EVENT_TYPE_COMP				= 0x00,
	SX_EVENT_TYPE_CMD				= 0x0a,
	SX_EVENT_TYPE_INTERNAL_ERROR	= 0x08
};

enum {
	SX_DBELL_REGION_SIZE		= 0xc00
};

struct completion_info {
	u8							swid;
	u16 						sysport;
	u16 						hw_synd;
	u8							is_send;
	enum sx_packet_type			pkt_type;
	struct sk_buff				*skb;
	union ku_filter_critireas	info;
	u8							is_lag;
	u8							lag_subport;
	u8							is_tagged;
	u16							vid;
	void						*context;
	struct sx_dev    		    *dev;
    u32                         original_packet_size;
    u16                         bridge_id;
};

typedef void (*cq_handler)(struct completion_info*, void *);

struct listener_entry {
	u8							swid;
	enum l2_type				listener_type;
	u8							is_default; /*is a default listener */
	union ku_filter_critireas	critireas;  /*more filter critireas */
	cq_handler					handler;    /*The completion handler*/
	void						*context;   /*to pass to the handler*/
	u64							rx_pkts;	/* rx pkts */
	struct list_head			list;
};

struct sx_stats{
	u64	rx_by_pkt_type[NUMBER_OF_SWIDS+1][PKT_TYPE_NUM];
	u64	tx_by_pkt_type[NUMBER_OF_SWIDS+1][PKT_TYPE_NUM];
	u64	rx_by_synd[NUMBER_OF_SWIDS+1][NUM_HW_SYNDROMES+1];
	u64	tx_by_synd[NUMBER_OF_SWIDS+1][NUM_HW_SYNDROMES+1];
	u64	rx_unconsumed_by_synd[NUM_HW_SYNDROMES+1][PKT_TYPE_NUM];
	u64	rx_eventlist_drops_by_synd[NUM_HW_SYNDROMES+1];
};

struct sx_dev {
	struct sx_dev_cap		dev_cap;
	spinlock_t				profile_lock; /* the profile's lock */
	struct sx_pci_profile	profile;
	u8						profile_set;
    u8 						dev_profile_set;
    u8                      first_ib_swid;
	unsigned long			flags;
	struct pci_dev			*pdev;
	u64						bar0_dbregs_offset;
	u8						bar0_dbregs_bar;
	void __iomem			*db_base;
	char					board_id[SX_BOARD_ID_LEN];
	u16						vsd_vendor_id;
	struct device			dev; /* TBD - do we need it? */
	u16						device_id;
	struct list_head		list;
	u64						fw_ver;
	u8						dev_stuck;
	u8						global_flushing;
	struct cdev             cdev;

	/* multi-dev support */
	struct sx_stats         stats;
	u64                     eventlist_drops_counter;
    u64                     unconsumed_packets_counter;
    u64                   filtered_lag_packets_counter;
    u64                   filtered_port_packets_counter;
	u64					loopback_packets_counter;
	struct work_struct catas_work;
	struct workqueue_struct *catas_wq;
	int         			catas_poll_running;
};

enum {
	PPBT_REG_ID = 0x3003,
	QSPTC_REG_ID = 0x4009,
	QSTCT_REG_ID = 0x400b,
	PMLP_REG_ID = 0x5002,
	PMTU_REG_ID = 0x5003,
	PTYS_REG_ID = 0x5004,
	PPAD_REG_ID = 0x5005,
	PAOS_REG_ID = 0x5006,
	PUDE_REG_ID = 0x5009,
	PLIB_REG_ID = 0x500a,
	PPTB_REG_ID = 0x500B,
	PSPA_REG_ID = 0x500d,
	PELC_REG_ID = 0x500e,
	PVLC_REG_ID = 0x500f,
	PMPR_REG_ID = 0x5013,
	SPZR_REG_ID = 0x6002,
	HCAP_REG_ID = 0x7001,
	HTGT_REG_ID = 0x7002,
	HPKT_REG_ID = 0x7003,
	HDRT_REG_ID = 0x7004,
	OEPFT_REG_ID = 0x7081,
	MFCR_REG_ID = 0x9001,
	MFSC_REG_ID = 0x9002,
	MFSM_REG_ID = 0x9003,
	MFSL_REG_ID = 0x9004,
	MTCAP_REG_ID = 0x9009,
	MTMP_REG_ID = 0x900a,
	MFPA_REG_ID = 0x9010,
	MFBA_REG_ID = 0x9011,
	MFBE_REG_ID = 0x9012,
	MCIA_REG_ID = 0x9014,
	MGIR_REG_ID = 0x9020,
	MRSR_REG_ID = 0x9023,
        MLCR_REG_ID = 0x902b,
	PMAOS_REG_ID = 0x5012,
	MFM_REG_ID = 0x901d,
	MJTAG_REG_ID = 0x901F,
	PMPC_REG_ID = 0x501F,
	MPSC_REG_ID = 0x9080,
};

enum {
	TLV_TYPE_END_E,
	TLV_TYPE_OPERATION_E,
	TLV_TYPE_DR_E,
	TLV_TYPE_REG_E,
	TLV_TYPE_USER_DATA_E
};

enum {
	EMAD_METHOD_QUERY = 1,
	EMAD_METHOD_WRITE = 2,
	EMAD_METHOD_SEND  = 3,
	EMAD_METHOD_EVENT = 5,
};

enum {
		PORT_OPER_STATUS_UP = 1,
		PORT_OPER_STATUS_DOWN = 2,
		PORT_OPER_STATUS_FAILURE = 4,
};

struct sx_eth_hdr {
	__be64	dmac_smac1;
	__be32	smac2;
	__be16	ethertype;
	u8		mlx_proto;
	u8		ver;
};

struct emad_operation {
	__be16  type_len;
	u8      status;
	u8      reserved1;
	__be16  register_id;
	u8      r_method;
	u8      class;
	__be64  tid;
};

struct sx_emad {
	struct sx_eth_hdr eth_hdr;
	struct emad_operation emad_op;
};

#define EMAD_TLV_TYPE_SHIFT (3)
struct sxd_emad_tlv_reg {
	u8     type;
	u8     len;
	__be16 reserved0;
};

struct sxd_emad_pude_reg {
	struct sx_emad emad_header;
	struct sxd_emad_tlv_reg tlv_header;
	u8     swid;
	u8     local_port;
	u8     admin_status;
	u8     oper_status;
	__be32 reserved3[3];
};

#define SX_PORT_PHY_ID_OFFS     (8)
#define SX_PORT_PHY_ID_MASK     (0x0000FF00)
#define SX_PORT_PHY_ID_ISO(id)  ((id) & (SX_PORT_PHY_ID_MASK)) 
#define SX_PORT_PHY_ID_GET(id)  (SX_PORT_PHY_ID_ISO(id) >> SX_PORT_PHY_ID_OFFS)

#define SX_PORT_DEV_ID_OFFS  (16) 
#define SX_PORT_DEV_ID_MASK  (0x0FFF0000)
#define SX_PORT_DEV_ID_ISO(id)  ((id) & (SX_PORT_DEV_ID_MASK))
#define SX_PORT_DEV_ID_GET(id)  (SX_PORT_DEV_ID_ISO(id) >> SX_PORT_DEV_ID_OFFS)

#define SX_PORT_TYPE_ID_OFFS (28)
#define SX_PORT_TYPE_ID_MASK (0xF0000000)
#define SX_PORT_TYPE_ID_ISO(id) ((id) & (SX_PORT_TYPE_ID_MASK))
#define SX_PORT_TYPE_ID_GET(id) (SX_PORT_TYPE_ID_ISO(id) >> SX_PORT_TYPE_ID_OFFS)

#define SX_PORT_LAG_ID_OFFS  (8)
#define SX_PORT_LAG_ID_MASK  (0x000FFF00)
#define SX_PORT_LAG_ID_ISO(id)  ((id) & (SX_PORT_LAG_ID_MASK))
#define SX_PORT_LAG_ID_GET(id)  (SX_PORT_LAG_ID_ISO(id) >> SX_PORT_LAG_ID_OFFS)

#define CPU_PORT_PHY_ID              (0)
#define UCROUTE_CPU_PORT_DEV_MASK    (0x0FC0)
#define UCROUTE_CPU_DEV_BIT_OFFSET   (6)
#define UCROUTE_DEV_ID_BIT_OFFSET    (10)
#define UCROUTE_PHY_PORT_BITS_OFFSET (4)
#define UCROUTE_CPU_PORT_PREFIX      (0xB000)

u16 translate_user_port_to_sysport(struct sx_dev *dev, u32 log_port, int* is_lag);
u32 translate_sysport_to_user_port(struct sx_dev *dev, u16 port, u8 is_lag);


#define SX_TRAP_ID_PUDE  0x08


#define NUM_OF_SYSPORT_BITS 16
#define NUM_OF_LAG_BITS 12
#define MAX_SYSPORT_NUM (1 << NUM_OF_SYSPORT_BITS)
#define MAX_PHYPORT_NUM 64
#define MAX_LAG_NUM MAX_PHYPORT_NUM
#define MAX_LAG_MEMBERS_NUM 32
#define MAX_IBPORT_NUM MAX_PHYPORT_NUM
#define MAX_SYSTEM_PORTS_IN_FILTER 256
#define MAX_LAG_PORTS_IN_FILTER 256
#define MAX_PRIO_NUM 15
#define MAX_VLAN_NUM 4096

/* Bridge Netdev values */
/* MIN_BRIDGE_ID = 4k */
#define MIN_BRIDGE_ID 4096
/* MAX_BRIDGE_ID = (15k - 1) */
#define MAX_BRIDGE_ID 15359
/* MAX_BRIDGE_NUM */
#define MAX_BRIDGE_NUM (MAX_BRIDGE_ID - MIN_BRIDGE_ID + 1)

/** This enum defines bitmask values for combinations of port types */
enum sx_port_type {
    SX_PORT_TYPE_NETWORK = 0,
    SX_PORT_TYPE_LAG = 1,
    SX_PORT_TYPE_VPORT = 2,
    SX_PORT_TYPE_MULTICAST = 4,
    SX_PORT_TYPE_MIN = SX_PORT_TYPE_NETWORK,
    SX_PORT_TYPE_MAX = SX_PORT_TYPE_MULTICAST,
};

/* Length of TLV in DWORDs*/
#define TLV_LEN 4

enum {
	TLV_REQUEST = 0,
	TLV_RESPONSE = 1,
};

enum {
	EMAD_CLASS_RESERVED 	= 0x00,
	EMAD_CLASS_REG_ACCESS 	= 0x01,
	EMAD_CLASS_IPC 		= 0x02,
};

#endif /* SX_DEVICE_H */
