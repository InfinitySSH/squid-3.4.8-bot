/*
 * DEBUG: section 49    SNMP Interface
 *
 */

#ifndef SQUID_SNMPX_SESSION_H
#define SQUID_SNMPX_SESSION_H

#include "ipc/forward.h"
#include "snmp.h"
#include "snmp_session.h"

namespace Snmp
{

/// snmp_session wrapper add pack/unpack feature
class Session: public snmp_session
{
public:
    Session();
    Session(const Session& session);
    Session& operator = (const Session& session);
    ~Session();

    void pack(Ipc::TypedMsgHdr& msg) const; ///< prepare for sendmsg()
    void unpack(const Ipc::TypedMsgHdr& msg); ///< restore struct from the message
    void clear(); ///< clear internal members

private:
    void free();  ///< free internal members
    void assign(const Session& session); ///< perform full assignment
};

} // namespace Snmp

#endif /* SQUID_SNMPX_SESSION_H */
